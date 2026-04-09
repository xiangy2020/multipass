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

#include "common.h"
#include "temp_dir.h"

#include <multipass/bz_image_decoder.h>
#include <multipass/rpc/multipass.grpc.pb.h>

#include <bzlib.h>

#include <algorithm>
#include <fstream>
#include <vector>

namespace mp = multipass;
namespace mpt = multipass::test;

using namespace testing;

namespace
{
static const std::string sample_content = "Hello from bz2 unit test\n";

// 使用 libbz2 在内存中生成合法的 .bz2 数据并写入文件
void create_test_bz2_file(const std::filesystem::path& path)
{
    std::ofstream f(path, std::ios::binary);
    ASSERT_TRUE(f.is_open());

    // 压缩 sample_content 为 bz2 格式
    unsigned int dest_len = static_cast<unsigned int>(sample_content.size() * 2 + 600);
    std::vector<char> dest(dest_len);

    int ret = BZ2_bzBuffToBuffCompress(dest.data(),
                                       &dest_len,
                                       const_cast<char*>(sample_content.data()),
                                       static_cast<unsigned int>(sample_content.size()),
                                       9,   // blockSize100k
                                       0,   // verbosity
                                       0);  // workFactor (0 = default)
    ASSERT_EQ(ret, BZ_OK) << "Failed to compress test data";

    f.write(dest.data(), dest_len);
    f.close();
}

void create_invalid_bz2_file(const std::filesystem::path& output_path)
{
    std::ofstream bz_file{output_path, std::ios::binary | std::ios::out};
    ASSERT_TRUE(bz_file.is_open());

    const char invalid_data[] = "This is not a bz2 file";
    bz_file.write(invalid_data, sizeof(invalid_data));
    bz_file.close();
}

// 用于测试的进度监控 Mock
class MockProgressMonitor
{
public:
    MOCK_METHOD(bool, call, (int, int), (const));

    mp::ProgressMonitor get_monitor()
    {
        return [this](int progress_type, int percentage) {
            call(progress_type, percentage);
            return true;
        };
    }
};
} // namespace

struct BzImageDecoder : public Test
{
    mpt::TempDir temp_dir;
    mp::BzImageDecoder decoder;
    std::filesystem::path bz_file_path;
    std::filesystem::path output_file_path;

    void SetUp() override
    {
        bz_file_path = temp_dir.filePath("test.bz2").toStdString();
        output_file_path = temp_dir.filePath("output.img").toStdString();
    }
};

TEST_F(BzImageDecoder, throwsWhenInputFileDoesNotExist)
{
    const auto non_existent_path = temp_dir.filePath("non_existent.bz2").toStdString();
    MockProgressMonitor monitor;

    MP_EXPECT_THROW_THAT(
        decoder.decode_to(non_existent_path, output_file_path, monitor.get_monitor()),
        std::runtime_error,
        mpt::match_what(AllOf(HasSubstr("failed to open"), HasSubstr("for reading"))));
}

TEST_F(BzImageDecoder, throwsWhenOutputFileCannotBeCreated)
{
    create_test_bz2_file(bz_file_path);

    const auto invalid_output =
        std::filesystem::path("/invalid/path/that/does/not/exist/output.img");
    MockProgressMonitor monitor;

    MP_EXPECT_THROW_THAT(
        decoder.decode_to(bz_file_path, invalid_output, monitor.get_monitor()),
        std::runtime_error,
        mpt::match_what(AllOf(HasSubstr("failed to open"), HasSubstr("for writing"))));
}

TEST_F(BzImageDecoder, throwsOnInvalidBz2Format)
{
    create_invalid_bz2_file(bz_file_path);
    MockProgressMonitor monitor;

    EXPECT_THROW(decoder.decode_to(bz_file_path, output_file_path, monitor.get_monitor()),
                 std::runtime_error);
}

TEST_F(BzImageDecoder, callsProgressMonitorDuringDecoding)
{
    create_test_bz2_file(bz_file_path);
    MockProgressMonitor monitor;

    // 解压过程中至少调用一次 EXTRACT 类型的进度回调
    EXPECT_CALL(monitor, call(mp::LaunchProgress::EXTRACT, _)).Times(AtLeast(1));

    decoder.decode_to(bz_file_path, output_file_path, monitor.get_monitor());
}

TEST_F(BzImageDecoder, progressMonitorReportsValidPercentages)
{
    create_test_bz2_file(bz_file_path);

    std::vector<int> reported_percentages;
    auto progress_monitor = [&reported_percentages](int progress_type, int percentage) -> bool {
        if (progress_type == mp::LaunchProgress::EXTRACT)
        {
            reported_percentages.push_back(percentage);
        }
        return true;
    };

    decoder.decode_to(bz_file_path, output_file_path, progress_monitor);

    EXPECT_FALSE(reported_percentages.empty());

    for (const auto percentage : reported_percentages)
    {
        EXPECT_GE(percentage, 0);
        EXPECT_LE(percentage, 100);
    }
}

TEST_F(BzImageDecoder, outputFileIsCreated)
{
    create_test_bz2_file(bz_file_path);
    MockProgressMonitor monitor;

    EXPECT_CALL(monitor, call(_, _)).Times(AtLeast(0));

    decoder.decode_to(bz_file_path, output_file_path, monitor.get_monitor());

    EXPECT_TRUE(std::filesystem::exists(output_file_path));
}

TEST_F(BzImageDecoder, outputFileHasExpectedContent)
{
    create_test_bz2_file(bz_file_path);
    MockProgressMonitor monitor;

    EXPECT_CALL(monitor, call(_, _)).Times(AtLeast(0));

    decoder.decode_to(bz_file_path, output_file_path, monitor.get_monitor());

    std::ifstream output_file{output_file_path, std::ios::binary};
    ASSERT_TRUE(output_file.is_open());

    std::string output_content((std::istreambuf_iterator<char>(output_file)),
                               std::istreambuf_iterator<char>());

    EXPECT_EQ(output_content, sample_content);
}
