# taken from Base.hash for String
function Base.hash(x::Tuple{Ptr{UInt8},Int}, h::UInt)
    h += Base.memhash_seed
    ccall(Base.memhash, UInt, (Ptr{UInt8}, Csize_t, UInt32), x[1], x[2], h % UInt32) + h
end
Base.isequal(x::Tuple{Ptr{UInt8}, Int}, y::String) = hash(x) === hash(y)
Base.convert(::Type{String}, x::Tuple{Ptr{UInt8}, Int}) = unsafe_string(x[1], x[2])

const BUF = IOBuffer()
getptr(io::IO) = pointer(BUF.data, BUF.ptr)
getptr(io::IOBuffer) = pointer(io.data, io.ptr)
incr(io::IO, b) = Base.write(BUF, b)
incr(io::IOBuffer, b) = 1

function xparse(io::IO, ::Type{String};
    quotechar::Union{UInt8, Nothing}=nothing,
    escapechar::Union{UInt8, Nothing}=quotechar,
    delims::Union{Vector{UInt8}, Nothing}=nothing,
    kwargs...)
    ptr = getptr(io)
    len = 0
    if quotechar !== nothing
        same = quotechar === escapechar
        eof(io) && return Result("", INVALID_QUOTED_FIELD, nothing)
        b = peekbyte(io)
        while true
            if same && b == escapechar
                pos = position(io)
                readbyte(io)
                if eof(io)
                    seek(io, pos)
                    @goto done
                elseif peekbyte(io) !== quotechar
                    seek(io, pos)
                    @goto done
                end
                # otherwise, next byte is escaped, so read it
                len += incr(io, b)
            elseif b == escapechar
                b = readbyte(io)
                eof(io) && return Result(InternedStrings.intern(String, (ptr, len)), INVALID_QUOTED_FIELD, b)
                # regular escaped byte
                len += incr(io, b)
            elseif b == quotechar
                @goto done
            end
            len += incr(io, b)
            b = readbyte(io)
            eof(io) && return Result(InternedStrings.intern(String, (ptr, len)), INVALID_QUOTED_FIELD, b)
            b = peekbyte(io)
        end
    elseif delims !== nothing
        eof(io) && @goto done
        # read until we find a delimiter
        b = peekbyte(io)
        while true
            for delim in delims
                if b === delim
                    @goto done
                end
            end
            len += incr(io, b)
            readbyte(io)
            eof(io) && @goto done
            b = peekbyte(io)
        end
    else
        # just read until eof
        while !eof(io)
            b = readbyte(io)
            len += incr(io, b) 
        end
    end
@label done
    return Result(InternedStrings.intern(String, (ptr, len)), OK, nothing)
end

function xparse(s::Sentinel, ::Type{String};
    quotechar::Union{UInt8, Nothing}=nothing,
    escapechar::Union{UInt8, Nothing}=quotechar,
    delims::Union{Vector{UInt8}, Nothing}=nothing,
    kwargs...)
    io = getio(s)
    ptr = getptr(io)
    len = 0
    trie = s.sentinels
    node = nothing
    if quotechar !== nothing
        same = quotechar === escapechar
        eof(io) && return Result("", INVALID_QUOTED_FIELD, nothing)
        b = peekbyte(io)
        prevnode = node = Tries.matchleaf(trie, io, b)
        while true
            if same && b == escapechar
                pos = position(io)
                readbyte(io)
                if eof(io)
                    seek(io, pos)
                    node = prevnode
                    @goto done
                elseif peekbyte(io) !== quotechar
                    seek(io, pos)
                    node = prevnode
                    @goto done
                end
                # otherwise, next byte is escaped, so read it
                len += incr(io, b)
            elseif b == escapechar
                b = readbyte(io)
                eof(io) && return Result(InternedStrings.intern(String, (ptr, len)), INVALID_QUOTED_FIELD, b)
                len += incr(io, b)
            elseif b == quotechar
                node = prevnode
                @goto done
            end
            prevnode = node
            len += incr(io, b)
            readbyte(io)
            eof(io) && return Result(InternedStrings.intern(String, (ptr, len)), INVALID_QUOTED_FIELD, b)
            b = peekbyte(io)
            node = Tries.matchleaf(node, io, b)
        end
    elseif delims !== nothing
        eof(io) && @goto done
        # read until we find a delimiter
        b = peekbyte(io)
        node = Tries.matchleaf(trie, io, b)
        while true
            for delim in delims
                if b === delim
                    @goto done
                end
            end
            len += incr(io, b)
            readbyte(io)
            eof(io) && @goto done
            b = peekbyte(io)
            node = Tries.matchleaf(node, io, b)
        end
    else
        # just read until eof
        eof(io) && @goto done
        b = peekbyte(io)
        node = Tries.matchleaf(trie, io, b)
        while true
            len += incr(io, b)
            readbyte(io)
            eof(io) && @goto done
            b = peekbyte(io)
            node = Tries.matchleaf(node, io, b)
        end
    end
@label done
    if node !== nothing && node.leaf
        return Result{Union{String, Missing}}(missing, OK, nothing)
    elseif isempty(trie) && len == 0
        return Result{Union{String, Missing}}(missing, OK, nothing)
    else
        return Result{Union{String, Missing}}(InternedStrings.intern(String, (ptr, len)), OK, nothing)
    end
end