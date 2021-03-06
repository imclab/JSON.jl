module Parser #JSON
  
const TYPES = Any # Union(Dict, Array, String, Number, Bool, Nothing) # Types it may encounter
const KEY_TYPES = Union(String) # Types it may encounter as object keys

export parse

# UTILITIES

function _search(haystack::String, needle::Union(String, Regex, Char), _start::Int)
    range = search(haystack, needle, _start)
    first(range), last(range)
end

# Eat up spaces starting at s.
function chomp_space(str::String, s::Int, e::Int)
    c = str[s]
    while (c == ' ' || c == '\t' || c == '\n' || c=='\r') && s<e
        s += 1
        c = str[s]
    end
    s
end

# Used for line counts
function _count_before(haystack::String, needle::Char, _end::Int)
    count = 0
    i = 1
    while i < _end
        haystack[i]==needle && (count += 1)
        i += 1
    end
    count
end

# Prints an error message with an indicator to the source
function _error(message::String, str::String, s::Int, e::Int)
    lines = _count_before(str, '\n', s)
    # Replace all special multi-line/multi-space characters with a space.
    strnl = replace(str, r"[\b\f\n\r\t\s]", " ")
    li = (s > 20) ? s - 9 : 1 # Left index
    ri = min(e, s + 20)       # Right index
    error(message *
      "\nLine: " * string(lines) *
      "\nAround: ..." * strnl[li:ri] * "..." *
      "\n           " * (" " ^ (s - li)) * "^\n"
    )
end

# PARSING

function parse_array(str::String, s::Int, e::Int)
    s += 1 # Skip over the '['
    _array = TYPES[]
    s = chomp_space(str, s, e)
    str[s]==']' && return _array, s+1, e # Check for empty array
    while true # Extract values from array
        v, s, e = parse_value(str, s, e) # Extract value
        push!(_array, v)
        # Eat up trailing whitespace
        s = chomp_space(str, s, e)
        c = str[s]
        if c == ','
            s += 1
            continue
        elseif c == ']'
            s += 1
            break
        else
            _error("Unexpected char: " * string(c), str, s, e)
        end
    end
    return _array, s, e
end

function parse_object(str::String, s::Int, e::Int)
    s += 1 # Skip over opening '{'
    obj = Dict{KEY_TYPES,TYPES}()
    s = chomp_space(str, s, e)
    str[s]=='}' && return obj, s+1, e # Check for empty object
    while true
        s = chomp_space(str, s, e)
        _key, s, e = parse_string(str, s, e)  # Key
        ss, se = _search(str, ':', s)         # Separator
        # TODO: Error handling if it doesn't find the separator
        ss < 1 && _error( "Separator not found ", str, s, e)
        s = se + 1                            # Skip over separator
        _value, s, e = parse_value(str, s, e) # Value
        obj[_key] = _value                    # Building object
        s = chomp_space(str, s, e)
        c = str[s] # Find the next pair or end of object
        if c == ','
            s += 1
            continue
        elseif c == '}'
            s += 1
            break
        else
            _error("Unexpected char: " * string(c), str, s, e)
        end
    end
    return obj, s, e
end

# TODO: Try to find ways to improve the performance of this (currently one
#       of the slowest parsing methods).
function parse_string(str::String, s::Int, e::Int)
    str[s]=='"' || _error("Missing opening string char", str, s, e)
    s = nextind(str, s) # Skip over opening '"'
    b = IOBuffer()
    found_end = false
    while s <= e
        c = str[s]
        if c == '\\'
            s = nextind(str, s)
            c = str[s]
            if c == 'u' # Unicode escape
                u = unescape_string(str[s - 1:s + 4]) # Get the string
                d = bytestring(u).data # Get the uint8s for the string
                write(b, bytestring(u))
                # Skip over those next four characters
                [s = nextind(str, s) for _ = 1:4]
            elseif c == '"'  write(b, '"' )
            elseif c == '\\' write(b, '\\')
            elseif c == '/'  write(b, '/' )
            elseif c == 'b'  write(b, '\b')
            elseif c == 'f'  write(b, '\f')
            elseif c == 'n'  write(b, '\n')
            elseif c == 'r'  write(b, '\r')
            elseif c == 't'  write(b, '\t')
            else _error("Unrecognized escaped character: " * string(c), str, s, e)
            end
        elseif c == '"'
            found_end = true
            s = nextind(str, s)
            break
        else
            write(b, c)
        end
        s = nextind(str, s)
    end
    
    found_end || _error("Unterminated string", str, s, e)
    r = takebuf_string(b)
    r, s, e
end

function parse_simple(str::String, s::Int, e::Int)
    c = str[s]
    if c == 't' && str[s + 3] == 'e'     # Looks like "true"
        ret = (true, s + 4, e)
    elseif c == 'f' && str[s + 4] == 'e' # Looks like "false"
        ret = (false, s + 5, e)
    elseif c == 'n' && str[s + 3] == 'l' # Looks like "null"
        ret = (nothing, s + 4, e)
    else
        _error("Unknown simple: " * string(c), str, s, e)
    end
    ret
end

function parse_value(str::String, s::Int, e::Int)
    s = chomp_space(str, s, e)
    s==e && return nothing, s, e # Nothing left
    
    ch = str[s]
    if ch == '"' ret = parse_string(str, s, e)
    elseif ch == '{'
        ret = parse_object(str, s, e)
    elseif (ch >= '0' && ch <= '9') || ch=='-' || ch=='+'
        ret = parse_number(str, s, e)
    elseif ch == '['
        ret = parse_array(str, s, e)
    elseif ch == 'f' || ch == 't' || ch == 'n'
        ret = parse_simple(str, s, e)
    else
        _error("Unknown value", str, s, e)
    end
    return ret
end

function parse_number(str::String, s::Int, e::Int)
    p = s
    if str[p]=='-' || str[p]=='+' # Look for sign
        p += 1
    end
    if str[p] == '0' # Look for number
        p += 1
        if str[p] == '.'
            is_float = true
            p += 1
        else
            is_float = false
        end
    elseif str[p] > '0' && str[p] <= '9'
        p += 1
        # Match more digits
        while str[p] >= '0' && str[p] <= '9'
            p += 1
        end
        if str[p] == '.'
            p += 1
            is_float = true
        else
            is_float = false
        end
    else
        _error("Unrecognized number", str, p, e)
    end
    if is_float # Match digits after decimal
        while str[p] >= '0' && str[p] <= '9'
            p += 1
        end
    end
    if str[p] == 'E' || str[p] == 'e' || str[p] == 'f' || str[p] == 'F'
        is_float = true
        p += 1
        if str[p] == '-' || str[p] == '+' # Exponent sign
            p += 1
        end
        while str[p] >= '0' && str[p] <= '9' # Exponent digits
            p += 1
        end
    end
    
    vs = str[s:p-1]
    v = (is_float ? parsefloat : parseint)(vs)
    return v, p, e
end

function parse(str::String)
    pos::Int = 1
    len::Int = endof(str)
    len < 1 && return
    
    v, s, e = parse_value(str, pos, len)
    return v
end

end #module Parser
