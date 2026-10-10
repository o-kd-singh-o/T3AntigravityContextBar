import unittest
from t3_monitor.proto import (
    decode_varint,
    encode_varint,
    parse_proto,
    extract_token_usage,
    TokenUsage,
)


class TestProtobufParser(unittest.TestCase):
    def test_varint_encode_decode_roundtrip(self):
        numbers = [0, 1, 127, 128, 300, 16384, 97558, 120000, 1048576]
        for n in numbers:
            encoded = encode_varint(n)
            decoded, pos = decode_varint(encoded, 0)
            self.assertEqual(decoded, n)
            self.assertEqual(pos, len(encoded))

    def test_extract_tokens_with_cached_context(self):
        # Construct synthetic protobuf matching Google Gemini UsageMetadata in Antigravity:
        # Submessage (field 4):
        # field 2: uncached prompt tokens (varint = 5032)
        # field 3: completion tokens (varint = 331)
        # field 5: cached content tokens (varint = 97558)
        # field 9: thought tokens (varint = 150)
        # field 10: text tokens (varint = 181)
        submsg = bytearray()
        # field 2 (tag = (2 << 3) | 0 = 16 = 0x10)
        submsg.extend(encode_varint((2 << 3) | 0))
        submsg.extend(encode_varint(5032))
        # field 3 (tag = (3 << 3) | 0 = 24 = 0x18)
        submsg.extend(encode_varint((3 << 3) | 0))
        submsg.extend(encode_varint(331))
        # field 5 (tag = (5 << 3) | 0 = 40 = 0x28)
        submsg.extend(encode_varint((5 << 3) | 0))
        submsg.extend(encode_varint(97558))
        # field 9 (tag = (9 << 3) | 0 = 72 = 0x48)
        submsg.extend(encode_varint((9 << 3) | 0))
        submsg.extend(encode_varint(150))
        # field 10 (tag = (10 << 3) | 0 = 80 = 0x50)
        submsg.extend(encode_varint((10 << 3) | 0))
        submsg.extend(encode_varint(181))

        # Root submessage (field 1):
        # field 4: length-delimited containing submsg
        f1_body = bytearray()
        f1_body.extend(encode_varint((4 << 3) | 2))
        f1_body.extend(encode_varint(len(submsg)))
        f1_body.extend(submsg)

        # Root message:
        # field 1: length-delimited containing f1_body
        root_msg = bytearray()
        root_msg.extend(encode_varint((1 << 3) | 2))
        root_msg.extend(encode_varint(len(f1_body)))
        root_msg.extend(f1_body)

        usage = extract_token_usage(bytes(root_msg))
        self.assertIsNotNone(usage)
        self.assertEqual(usage.uncached_tokens, 5032)
        self.assertEqual(usage.cached_tokens, 97558)
        self.assertEqual(usage.total_prompt_tokens, 102590)  # 5032 + 97558
        self.assertEqual(usage.completion_tokens, 331)
        self.assertEqual(usage.thought_tokens, 150)

    def test_extract_tokens_without_cache(self):
        # Initial turn without cache (only field 2 and field 3)
        submsg = bytearray()
        # field 2: prompt tokens = 19038
        submsg.extend(encode_varint((2 << 3) | 0))
        submsg.extend(encode_varint(19038))
        # field 3: completion tokens = 1226
        submsg.extend(encode_varint((3 << 3) | 0))
        submsg.extend(encode_varint(1226))

        f1_body = bytearray()
        f1_body.extend(encode_varint((4 << 3) | 2))
        f1_body.extend(encode_varint(len(submsg)))
        f1_body.extend(submsg)

        root_msg = bytearray()
        root_msg.extend(encode_varint((1 << 3) | 2))
        root_msg.extend(encode_varint(len(f1_body)))
        root_msg.extend(f1_body)

        usage = extract_token_usage(bytes(root_msg))
        self.assertIsNotNone(usage)
        self.assertEqual(usage.uncached_tokens, 19038)
        self.assertEqual(usage.cached_tokens, 0)
        self.assertEqual(usage.total_prompt_tokens, 19038)
        self.assertEqual(usage.completion_tokens, 1226)

    def test_extract_tokens_invalid_or_empty(self):
        self.assertIsNone(extract_token_usage(b""))
        self.assertIsNone(extract_token_usage(b"random garbage not protobuf"))
        self.assertIsNone(extract_token_usage(b"\x08\x01"))  # valid proto field 1 varint, but no token metadata


if __name__ == "__main__":
    unittest.main()
