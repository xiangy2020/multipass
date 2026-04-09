/*
 * Copyright (C) Canonical, Ltd.
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; version 3.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 *
 */

#include <multipass/bz_image_decoder.h>
#include <multipass/rpc/multipass.grpc.pb.h>

#include <fmt/format.h>

#include <bzlib.h>

#include <cstdio>
#include <filesystem>
#include <fstream>
#include <stdexcept>
#include <vector>

namespace mp = multipass;

void mp::BzImageDecoder::decode_to(const std::filesystem::path& bz_file_path,
                                   const std::filesystem::path& decoded_image_path,
                                   const ProgressMonitor& monitor) const
{
    // 使用 C 文件句柄，因为 libbz2 的 BZ2_bzReadOpen 需要 FILE*
    FILE* raw_file = std::fopen(bz_file_path.string().c_str(), "rb");
    if (!raw_file)
        throw std::runtime_error{
            fmt::format("failed to open {} for reading", bz_file_path.string())};

    std::ofstream decoded_file{decoded_image_path, std::ios::binary | std::ios::out};
    if (!decoded_file.is_open())
    {
        std::fclose(raw_file);
        throw std::runtime_error{
            fmt::format("failed to open {} for writing", decoded_image_path.string())};
    }

    int bz_error = BZ_OK;
    BZFILE* bz_file = BZ2_bzReadOpen(&bz_error, raw_file, 0, 0, nullptr, 0);
    if (bz_error != BZ_OK)
    {
        std::fclose(raw_file);
        throw std::runtime_error{
            fmt::format("failed to open bz2 stream in {}: error code {}", bz_file_path.string(), bz_error)};
    }

    const auto file_size = std::filesystem::file_size(bz_file_path);
    std::int64_t total_bytes_read{0};
    auto last_progress = -1;

    constexpr auto buf_size = 65536u;
    std::vector<char> buf(buf_size);

    while (true)
    {
        int bytes_read = BZ2_bzRead(&bz_error, bz_file, buf.data(), static_cast<int>(buf_size));

        if (bz_error == BZ_MEM_ERROR)
        {
            BZ2_bzReadClose(&bz_error, bz_file);
            std::fclose(raw_file);
            throw std::runtime_error{"bz2 decoder memory allocation failed"};
        }

        if (bz_error != BZ_OK && bz_error != BZ_STREAM_END)
        {
            BZ2_bzReadClose(&bz_error, bz_file);
            std::fclose(raw_file);
            throw std::runtime_error{
                fmt::format("bz2 file is corrupt or invalid: error code {}", bz_error)};
        }

        if (bytes_read > 0)
        {
            decoded_file.write(buf.data(), bytes_read);
            if (!decoded_file)
            {
                BZ2_bzReadClose(&bz_error, bz_file);
                std::fclose(raw_file);
                throw std::runtime_error{
                    fmt::format("failed to write to {}", decoded_image_path.string())};
            }
        }

        // 用已读取的压缩文件字节数估算进度
        total_bytes_read = static_cast<std::int64_t>(std::ftell(raw_file));
        if (file_size > 0)
        {
            auto progress = static_cast<int>((total_bytes_read / static_cast<float>(file_size)) * 100);
            if (last_progress != progress)
            {
                monitor(LaunchProgress::EXTRACT, progress);
                last_progress = progress;
            }
        }

        if (bz_error == BZ_STREAM_END)
            break;
    }

    BZ2_bzReadClose(&bz_error, bz_file);
    std::fclose(raw_file);
}
