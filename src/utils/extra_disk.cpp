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

#include <multipass/extra_disk.h>
#include <multipass/memory_size.h>

#include <boost/json.hpp>

namespace mp = multipass;

void mp::tag_invoke(const boost::json::value_from_tag&,
                    boost::json::value& json,
                    const mp::ExtraDisk& disk)
{
    json = {{"id", disk.id},
            {"path", disk.path},
            {"size", std::to_string(disk.size.in_bytes())}};
}

mp::ExtraDisk mp::tag_invoke(const boost::json::value_to_tag<mp::ExtraDisk>&,
                              const boost::json::value& json)
{
    auto id = boost::json::value_to<std::string>(json.at("id"));
    auto path = boost::json::value_to<std::string>(json.at("path"));
    auto size_str = boost::json::value_to<std::string>(json.at("size"));

    return {id, path, mp::MemorySize{size_str.empty() ? "0" : size_str}};
}
