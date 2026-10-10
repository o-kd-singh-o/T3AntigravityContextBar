"""Pure Python Protocol Buffers decoder for Antigravity telemetry metadata."""

from dataclasses import dataclass
from typing import Optional, List, Tuple, Any


@dataclass(frozen=True)
class TokenUsage:
    """Token usage metrics extracted from Gemini metadata."""
    total_prompt_tokens: int
    cached_tokens: int
    uncached_tokens: int
    completion_tokens: int
    thought_tokens: int = 0


def encode_varint(value: int) -> bytes:
    """Encode an unsigned integer as a protobuf varint."""
    if value < 0:
        raise ValueError("Varint values must be non-negative")
    res = bytearray()
    while True:
        towrite = value & 0x7F
        value >>= 7
        if value:
            res.append(towrite | 0x80)
        else:
            res.append(towrite)
            break
    return bytes(res)


def decode_varint(stream: bytes | bytearray, pos: int = 0) -> Tuple[int, int]:
    """Decode a protobuf varint starting at `pos`.
    
    Returns (value, next_pos).
    Raises ValueError if the stream ends prematurely.
    """
    res = 0
    shift = 0
    length = len(stream)
    while pos < length:
        b = stream[pos]
        pos += 1
        res |= (b & 0x7F) << shift
        if not (b & 0x80):
            return res, pos
        shift += 7
        if shift > 64:
            raise ValueError("Varint exceeds 64 bits")
    raise ValueError("Truncated varint stream")


def parse_proto(stream: bytes | bytearray) -> List[Tuple[int, int, Any]]:
    """Parse raw protobuf bytes into a list of (field_number, wire_type, value).
    
    Wire types:
      0: varint (value is int)
      1: 64-bit (value is bytes of length 8)
      2: length-delimited (value is bytes)
      5: 32-bit (value is bytes of length 4)
    """
    fields: List[Tuple[int, int, Any]] = []
    pos = 0
    stream_len = len(stream)

    while pos < stream_len:
        try:
            tag, next_pos = decode_varint(stream, pos)
        except (ValueError, IndexError):
            break

        field_num = tag >> 3
        wire_type = tag & 0x07

        if field_num == 0:
            break

        if wire_type == 0:  # varint
            try:
                val, pos = decode_varint(stream, next_pos)
                fields.append((field_num, wire_type, val))
            except (ValueError, IndexError):
                break
        elif wire_type == 1:  # 64-bit fixed
            if next_pos + 8 > stream_len:
                break
            val = bytes(stream[next_pos:next_pos + 8])
            pos = next_pos + 8
            fields.append((field_num, wire_type, val))
        elif wire_type == 2:  # length-delimited
            try:
                length, p = decode_varint(stream, next_pos)
            except (ValueError, IndexError):
                break
            if p + length > stream_len:
                break
            val = bytes(stream[p:p + length])
            pos = p + length
            fields.append((field_num, wire_type, val))
        elif wire_type == 5:  # 32-bit fixed
            if next_pos + 4 > stream_len:
                break
            val = bytes(stream[next_pos:next_pos + 4])
            pos = next_pos + 4
            fields.append((field_num, wire_type, val))
        else:
            # Unsupported wire type (group or invalid)
            break

    return fields


def extract_token_usage(blob: bytes) -> Optional[TokenUsage]:
    """Extract TokenUsage from gen_metadata blob.
    
    Structure in Antigravity conversation DB:
      Root:
        Field 1 (length-delimited):
          Field 4 (length-delimited):
            Field 2 (varint): uncached prompt tokens (or total prompt if cached == 0)
            Field 3 (varint): candidates/completion tokens
            Field 5 (varint): cached content tokens
            Field 9 (varint): thought reasoning tokens
            Field 10 (varint): text candidate tokens
    """
    if not blob:
        return None

    try:
        root_fields = parse_proto(blob)
        for fnum, fwire, fval in root_fields:
            if fnum == 1 and fwire == 2 and isinstance(fval, (bytes, bytearray)):
                subfields = parse_proto(fval)
                for sfnum, sfwire, sfval in subfields:
                    if sfnum == 4 and sfwire == 2 and isinstance(sfval, (bytes, bytearray)):
                        meta_fields = parse_proto(sfval)
                        field_map = {num: val for num, wire, val in meta_fields if wire == 0}

                        # Check if token fields are present
                        if 2 in field_map or 5 in field_map:
                            uncached = field_map.get(2, 0)
                            cached = field_map.get(5, 0)
                            completion = field_map.get(3, 0)
                            thought = field_map.get(9, 0)
                            
                            # Total effective prompt tokens loaded into context window
                            total_prompt = cached + uncached if cached else uncached

                            return TokenUsage(
                                total_prompt_tokens=total_prompt,
                                cached_tokens=cached,
                                uncached_tokens=uncached,
                                completion_tokens=completion,
                                thought_tokens=thought,
                            )
    except Exception:
        return None

    return None
