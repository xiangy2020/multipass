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

#pragma once

#include <multipass/memory_size.h>

#include <boost/json.hpp>

#include <string>

namespace multipass
{

/**
 * 描述一块额外数据磁盘的配置信息。
 * - id:   磁盘设备标识符，如 "hdb"、"hdc"，用于 QEMU 参数生成
 * - path: 磁盘镜像文件的绝对路径（qcow2 格式）
 * - size: 磁盘大小
 */
struct ExtraDisk
{
    std::string id;   // 设备 ID，如 "hdb"
    std::string path; // 镜像文件路径
    MemorySize size;  // 磁盘大小

    friend inline bool operator==(const ExtraDisk& a, const ExtraDisk& b) = default;
};

void tag_invoke(const boost::json::value_from_tag&,
                boost::json::value& json,
                const ExtraDisk& disk);
ExtraDisk tag_invoke(const boost::json::value_to_tag<ExtraDisk>&, const boost::json::value& json);

} // namespace multipass
