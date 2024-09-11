-- fmt.lua - v1.1 - https://github.com/chrg127/lua-utils
-- no warranty implied, use at your own risk
--
-- This is a library for formatting and printing.
--
-- It is written in pure Lua and can be run in both PUC-Rio Lua and LuaJIT.
--
-- Notably, it provides print() and tostring() functions that correctly print
-- table contents, styling them like so:
--
--     "{ [key1] = value1, [key2] = value2, ... }"
--
-- It also provides a format() function that is equivalent to python's format
-- function (minus a few features, see the function's specific documentation).
-- This format function also adds a way to format tables indented (an extension).
--
-- More details are provided in each functions's documentation.
--
-- HOW TO USE:
--
-- fmt = require "fmt"
-- fmt.print(args...)                 -- for printing, same as lua print()
-- fmt.tostring(args...)              -- stringify args, same as lua tostring()
-- fmt.format_table(table, options?)  -- for formatting a table specifically
-- fmt.print_opts(opts, args...)      -- print() with options
-- fmt.tostring_opts(opts, args...)   -- tostring() with options
-- fmt.bin(n)                         -- convert number to binary
-- fmt.hex(n, upper)                  -- convert number to hex, lower or upper
-- fmt.format(format_string, args...) -- for formatting to a string

local fmt = {}

local old_tostring = tostring
local old_print = print

local function is_nan(n) return n ~= n end
local function is_inf(n) return n == math.huge or n == -math.huge end

local pack = table.pack or function(...)
    return { n = select('#', ...), ... }
end

-- Formats a table `t` according to `opts`.
-- `opts` can be either `nil` or a table containing these entries:
--   - `indent` (number): indent size of a table.
--                        0 (default) means don't indent.
--   - `show_ptr` (bool): show table pointer according to `tostring(t)`.
--                        Default is don't show.
function fmt.format_table(t, opts)
    function spaces(opts)
        return string.rep(" ", (opts.indent or 0) * (opts._depth or 1))
    end

    opts = opts or {}
    opts.indent = opts.indent or 0
    opts._depth = opts._depth or 0
    opts._locked = opts._locked or {}
    opts._locked[t] = true
    local line_end = (opts.indent ~= 0 and "\n" or "")
    if next(t) == nil then
        return spaces(opts) .. "{}"
    end
    local s = (opts.show_ptr and old_tostring(t) .. " " or "")
            .. "{" .. line_end
    opts._depth = opts._depth + 1
    local ss = spaces(opts)
    for k, v in pairs(t) do
        local key = type(k) == "string"
                  and k or "[" .. fmt.tostring_opts(opts, k) .. "]"
        s = s .. ss .. key .. " = "
              .. (opts._locked[v] and old_tostring(v)
                                  or  fmt.tostring_opts(opts, v))
              .. ", " .. line_end
    end
    s = s:sub(1, -3) .. line_end
    opts._depth = opts._depth - 1
    return s .. spaces(opts) .. "}"
end

-- Same as `tostring`, except it takes an `opts` argument. `opts` is only valid
-- fortables and works the same as `format_table`'s `opts` argument.
function fmt.tostring_opts(opts, ...)
    local args = pack(...)
    local s = ""
    for i = 1, args.n do
        s = s .. (type(args[i]) == "table"
                  and fmt.format_table(args[i], opts) .. " "
                  or  old_tostring(args[i]) .. " ")
    end
    return s:sub(1, -2)
end

-- Same as `print`, except it takes an `opts` argument. `opts` is only valid
-- fortables and works the same as `format_table`'s `opts` argument.
function fmt.print_opts(opts, ...) old_print(fmt.tostring_opts(opts, ...)) end

-- Converts a variable number of arguments to a single string. Each argument
-- is concatenated by a space.
-- If an argument is not a table, it is converted using lua `tostring`.
-- Otherwise it is converted using `format_table`.
function fmt.tostring(...) return fmt.tostring_opts(nil, ...) end

-- Prints a variable number of arguments using lua `print`. Conversion to
-- string happens the same as `tostring_opts`.
function fmt.print(...) return fmt.print_opts(nil, ...) end

-- Converts a number to binary.
function fmt.bin(n)
    local s = ""
    while n > 0 do
        local digit = n % 2
        s = (digit == 0 and "0" or "1") .. s
        n = math.floor(n / 2)
    end
    return s
end

-- Converts a number to hexadecimal. Defaults to printing letters in lowercase,
-- unless `upper` is set to `true`.
function fmt.hex(n, upper)
    local s = ""
    local t = upper and { "0", "1", "2", "3", "4", "5", "6", "7",
                          "8", "9", "A", "B", "C", "D", "E", "F" }
                    or  { "0", "1", "2", "3", "4", "5", "6", "7",
                          "8", "9", "a", "b", "c", "d", "e", "f" }
    while n > 0 do
        s = s .. t[(n % 16) + 1]
        n = math.floor(n / 16)
    end
    return s
end

local function parse_format_string(s)
    local i = 1
    local prev, cur = "", string.char(s:byte(i))

    local function advance()
        i = i + 1
        prev = cur
        cur = string.char(s:byte(i))
    end

    local function consume(c, error_string)
        if cur ~= c then
            error(error_string)
        end
        advance()
    end

    local function match(c)
        if cur == c then
            advance()
            return true
        end
        return false
    end

    local function collect_num(fail_val)
        local num = ""
        while cur >= "0" and cur <= "9" do
            num = num .. cur
            advance()
        end
        local n = tonumber(num)
        return n == nil and fail_val or n
    end

    local function arg_pos() return collect_num() end

    local function argument()
        local pos = arg_pos()
        consume("}")
        return { pos = pos }
    end

    local function align()
        local nextc = string.char(s:byte(i+1))
        if nextc == ">" or nextc == "<" or nextc == "=" or nextc == "^" then
            advance()
            local fill = prev
            advance()
            return fill, prev
        end
        if match(">") or match("<") or match("=") or match("^") then
            return " ", prev
        end
        return " ", nil
    end

    local function precision()
        return match("{") and argument() or collect_num()
    end

    local function typ()
            if match("s") then return "string"
        elseif match("?") then return "debug"
        elseif match("c") then return "char"
        elseif match("d") then return "decimal"
        elseif match("b") then return "binary"
        elseif match("o") then return "octal"
        elseif match("x") then return "hex", "lower"
        elseif match("X") then return "hex", "upper"
        elseif match("e") then return "scientific", "lower"
        elseif match("E") then return "scientific", "upper"
        elseif match("f") then return "fixed", "lower"
        elseif match("F") then return "fixed", "upper"
        elseif match("g") then return "general", "lower"
        elseif match("G") then return "general", "upper"
        elseif match("%") then return "percent"
        else                   return nil end
    end

    local function format_spec()
        local r = {}
        r.fill, r.align = align()
        r.sign          = (match("+") or match("-") or match(" ")) and prev or nil
        r.alt           = match("#")
        r.zero_pad      = match("0")
        r.width         = match("{") and argument() or collect_num(0)
        r.precision     = match(".") and precision() or nil
        r.typ, r.case   = typ()
        return r
    end

    local function replacement_field()
        consume("{", "expected { at start of format string")
        local r = {}
        local pos = arg_pos()
        local spec = match(":") and format_spec() or {
            fill = " ", width = 0, alt = false
        }
        spec.pos = pos
        consume("}", "expected } before end of format string, found " .. cur .. " instead")
        return spec
    end

    local r = replacement_field()
    return r, i
end

-- Format arguments according to `fmtstr`.
-- Literal text is copied wholesale; each instance of a replacement field
-- (delimited by braces `{}`) is substituted with an argument according to the
-- following syntax:
--
-- replacement_field ::=  "{" [arg_pos] [":" format_spec] "}"
-- arg_pos           ::=  [digit+]
-- format_spec       ::=  [[fill]align][sign]["#"]["0"][width]["." precision][type]
-- fill              ::=  <any character>
-- align             ::=  "<" | ">" | "=" | "^"
-- sign              ::=  "+" | "-" | " "
-- width             ::=  digit+
-- precision         ::=  digit+
-- type              ::=  "b" | "c" | "d" | "e" | "E" | "f" | "F"
--                      | "g" | "G" | "o" | "s" | "x" | "X" | "%"
--
-- Differences with python `format`:
--   - `arg_pos` can only be a number, not a variable name.
--     One can also mix replacement fields with an `arg_pos` and ones without:
--     in this case, fields without an `arg_pos` use an internal index variable
--     that goes up whenever one of these fields is encountered.
--   - `conversion` isn't supported.
--   - `grouping_option` isn't supported.
--   - Most types are supported except `n`. Because lua only has a single
--     number type, the default type is `d`, which simply outputs the number using
--     lua `tostring`, which is in most cases equivalent to `g`.
--   - Specifying both '#' and a `width` allows to format tables with indentation
--     (where `width` is taken as the indentation size).
function fmt.format(fmtstr, ...)
    local args, res, n, i = pack(...), "", 1, 1

    local function format_num(spec, num)
        function prefix(if_upper, if_lower)
            return (spec.alt and spec.case == "upper") and if_upper
                or  spec.alt and if_lower or ""
        end
        if spec.precision ~= nil and spec.typ ~= nil and spec.typ ~= "scientific"
            and spec.typ ~= "fixed" and spec.typ ~= "general" then
            error("precision not allowed in format specifier '" .. spec.typ .. "'")
        end
        if spec.typ == "decimal" or spec.typ == nil then
            return old_tostring(num)
        elseif spec.typ == "binary" then
            return prefix("0B", "0b") .. fmt.bin(num)
        elseif spec.typ == "hex" then
             return prefix("0X", "0x") .. fmt.bin(num, spec.case == "upper")
        elseif spec.typ == "octal" then
            return prefix("0O", "0o") .. string.format("%o", num)
        elseif spec.typ == "scientific" then
            return string.format("%" .. (spec.alt and "#" or "")
                                     .. "." .. (spec.precision == nil and 6 or spec.precision)
                                     .. (spec.case == "upper" and "E" or "e"), num)
        elseif spec.typ == "fixed" then
            return (spec.case == "upper" and is_nan(num)) and "NAN"
                or (spec.case == "upper" and is_inf(num)) and "INF"
                or string.format("%" .. (spec.alt and "#" or "")
                                     .. "." .. (spec.precision == nil and 6 or spec.precision)
                                     .. "f", num)
        elseif spec.typ == "general" then
            return (spec.case == "upper" and is_nan(num)) and "NAN"
                or (spec.case == "upper" and is_inf(num)) and "INF"
                or string.format("%" .. (spec.alt and "#" or "")
                                     .. "." .. (spec.precision == nil and 6 or spec.precision)
                                     .. (spec.case == "upper" and "G" or "g"), num)
        elseif spec.typ == "percent" then
            spec.typ = "fixed"
            return format_num(num * 100) .. "%"
        else
            return error("unknown format " .. spec.typ .. " for argument '" .. num .. "' of type 'number'")
        end
    end

    local function format_string(spec, arg)
        if spec.typ == "string" or spec.typ == nil then
            return arg:sub(spec.precision == nil and 0 or spec.precision)
        else
            error("invalid format '" .. spec.typ .. "' for argument '" .. arg .. "' of type 'string'")
        end
    end

    local function format_char(arg)
        if arg < 0 then
            error("character code out of range: " .. num)
        else
            return utf8 ~= nil and utf8.char(arg) or string.char(arg)
        end
    end

    local function format_table(spec, arg)
        return fmt.format_table(arg, spec.alt
            and { indent = spec.width == 0 and 4 or spec.width }
            or  {})
    end

    local function format_arg(spec, arg)
        local arg_type = type(arg)
        if spec.typ ~= nil and arg_type ~= "number" and arg_type ~= "string" then
            error("invalid format '" .. spec.typ .. "' for argument '" .. arg .. "' of type '" .. arg_type .. "'")
        end
        local s = spec.typ == "char" and format_char(arg)
               or arg_type == "number" and format_num(spec, math.abs(arg))
               or arg_type == "string" and format_string(spec, arg)
               or arg_type == "table" and format_table(spec, arg)
               or fmt.tostring(arg)
        if spec.sign ~= nil and arg_type ~= "number" then
            error("sign can't be used with argument '" .. arg .. "' of type '" .. arg_type .. "'")
        end
        local sign = arg_type ~= "number" and ""
                  or spec.typ == "percent" and ""
                  or spec.typ == "char" and ""
                  or spec.sign == "+" and (arg < 0 and "-" or "+")
                  or spec.sign == " " and (arg < 0 and "-" or " ")
                  or (arg < 0 and "-" or "")
        spec.fill = (spec.zero_pad and spec.fill == " ") and "0" or spec.fill
        if spec.align == "=" and arg_type ~= "number" then
            error("'=' alignment not allowed in argument '" .. arg .. "' of type '" .. arg_type .. "'")
        end
        spec.align = (spec.align == nil and arg_type == "number" and spec.zero_pad) and "="
                  or (spec.align == nil and arg_type == "number") and ">"
                  or spec.align == nil and "<" or spec.align
        if spec.align == "<" then
            return sign .. s .. string.rep(spec.fill, spec.width - #s - #sign)
        elseif spec.align == ">" then
            return string.rep(spec.fill, spec.width - #s - #sign) .. sign .. s
        elseif spec.align == "^" then
            local fill = string.rep(spec.fill, math.floor((spec.width - #s - #sign)/2))
            return fill .. sign .. s .. fill
        elseif spec.align == "=" then
            return sign .. string.rep(spec.fill, spec.width - #s - #sign) .. s
        end
    end

    local function get_arg(args, pos)
        if pos ~= nil then
            if pos < 1 or pos > #args then
                error("positional argument out of range")
            end
            return args[pos]
        else
            n = n + 1
            -- if n-1 > #args then
            --     error("not enough arguments, n = " .. tostring(n))
            -- end
            return args[n-1]
        end
    end

    local function dependent_arg(arg, name)
        if type(arg) == "table" then
            arg = get_arg(args, spec.width.pos)
            if type(arg) ~= "number" then
                error(name .. " must be a number")
            end
        end
        return arg
    end

    while i <= #fmtstr do
        if fmtstr:byte(i) == string.byte("{") then
            local spec, index = parse_format_string(fmtstr:sub(i))
            spec.width     = dependent_arg(spec.width, "width")
            spec.precision = dependent_arg(spec.precision, "precision")
            res = res .. format_arg(spec, get_arg(args, spec.pos))
            i = i + index
        else
            res = res .. string.char(fmtstr:byte(i))
        end
        i = i + 1
    end
    return res
end

-- Patches the global `print` and `tostring` to use fmt `print` and `tostring`.
-- This function can be called at `require`-time. It returns `fmt` to make sure
-- `require` still works correctly.
function fmt.patch_globals()
    _G.tostring = fmt.tostring
    _G.print = fmt.print
    return fmt
end

return setmetatable(fmt, { __call = fmt.patch_globals })

--[[
------------------------------------------------------------------------------
This software is available under 2 licenses -- choose whichever you prefer.
------------------------------------------------------------------------------
ALTERNATIVE A - MIT License
Copyright (c) 2017 Sean Barrett
Permission is hereby granted, free of charge, to any person obtaining a copy of
this software and associated documentation files (the "Software"), to deal in
the Software without restriction, including without limitation the rights to
use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies
of the Software, and to permit persons to whom the Software is furnished to do
so, subject to the following conditions:
The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.
THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
------------------------------------------------------------------------------
ALTERNATIVE B - Public Domain (www.unlicense.org)
This is free and unencumbered software released into the public domain.
Anyone is free to copy, modify, publish, use, compile, sell, or distribute this
software, either in source code form or as a compiled binary, for any purpose,
commercial or non-commercial, and by any means.
In jurisdictions that recognize copyright laws, the author or authors of this
software dedicate any and all copyright interest in the software to the public
domain. We make this dedication for the benefit of the public at large and to
the detriment of our heirs and successors. We intend this dedication to be an
overt act of relinquishment in perpetuity of all present and future rights to
this software under copyright law.
THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN
ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
------------------------------------------------------------------------------
]]
