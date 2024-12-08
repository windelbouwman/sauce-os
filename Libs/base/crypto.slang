
from math import modulo, sin, floor, fabs
from bytes import Bytes, ByteArray, ByteReader

pub fn md5(data: Bytes) -> Bytes:
    # RFC 1321
    # See also: https://en.wikipedia.org/wiki/MD5
    # And:  https://www.ietf.org/rfc/rfc1321.txt

    # Step 1: pad until almost modulo 512:
    let data2 = ByteArray()
    data2.extend(data)
    data2.append(0x80)
    while modulo(value: data2.len(), divisor: 64) != 56:
        data2.append(0)
    
    # Step 2: append length in bits
    data2.pack_u64_le(data.len() * 8)

    let a0 = 0x67452301
    let b0 = 0xefcdab89
    let c0 = 0x98badcfe
    let d0 = 0x10325476

    let s: [int] = [7, 12, 17, 22,  7, 12, 17, 22,  7, 12, 17, 22,  7, 12, 17, 22, 5,  9, 14, 20,  5,  9, 14, 20,  5,  9, 14, 20,  5,  9, 14, 20, 4, 11, 16, 23,  4, 11, 16, 23,  4, 11, 16, 23,  4, 11, 16, 23, 6, 10, 15, 21,  6, 10, 15, 21,  6, 10, 15, 21,  6, 10, 15, 21]
    let M: [int] = [16 : int]
    let K: [int] = [64 : int]
    fill_md5_K(K)

    let reader = ByteReader(m_bytes: data2.to_bytes())
    while not reader.at_end():
        let i = 0
        while i < 16:
            M[i] = reader.read_u32_le()
            i += 1

        let A = a0
        let B = b0
        let C = c0
        let D = d0

        i = 0
        while i < 64:
            let F = 0
            let g = 0
            if i < 16:
                F = (B & C) | ((0xFFffFFFF ^ B) & D)
                g = i
            elif i < 32:
                F = (D & B) | ((0xFFffFFFF ^ D) & C)
                g = modulo(value: 5 * i + 1, divisor: 16)
            elif i < 48:
                F = B ^ C ^ D
                g = modulo(value: 3 * i + 5, divisor: 16)
            else:
                F = C ^ (B | (0xFFFFFFFF ^ D))
                g = modulo(value: 7 * i, divisor: 16)
            F = wrap_u32(F + A + K[i] + M[g])
            A = D
            D = C
            C = B
            B = wrap_u32(B + leftrotate(value: F, amount: s[i]))

            i += 1

        a0 = wrap_u32(a0 + A)
        b0 = wrap_u32(b0 + B)
        c0 = wrap_u32(c0 + C)
        d0 = wrap_u32(d0 + D)
    
    let digest = ByteArray()
    digest.pack_u32_le(a0)
    digest.pack_u32_le(b0)
    digest.pack_u32_le(c0)
    digest.pack_u32_le(d0)
    digest.to_bytes()

pub fn leftrotate(value: int, amount: int) -> int:
    (0xffFFffFF & (value << amount)) | (value >> (32 - amount))

pub fn compute_md5_K(K: [int]):
    let i = 0
    while i < 64:
        K[i] = int(floor(fabs(sin(i + 1)) * 0x100000000))
        i += 1

pub fn fill_md5_K(K: [int]):
    """
    Pre computed table of
    floor(2^32 * abs(sin(i + 1)))
    """
    K[0] = 0xd76aa478
    K[1] = 0xe8c7b756
    K[2] = 0x242070db
    K[3] = 0xc1bdceee
    K[4] = 0xf57c0faf
    K[5] = 0x4787c62a
    K[6] = 0xa8304613
    K[7] = 0xfd469501
    K[8] = 0x698098d8
    K[9] = 0x8b44f7af
    K[10] = 0xffff5bb1
    K[11] = 0x895cd7be
    K[12] = 0x6b901122
    K[13] = 0xfd987193
    K[14] = 0xa679438e
    K[15] = 0x49b40821
    K[16] = 0xf61e2562
    K[17] = 0xc040b340
    K[18] = 0x265e5a51
    K[19] = 0xe9b6c7aa
    K[20] = 0xd62f105d
    K[21] = 0x02441453
    K[22] = 0xd8a1e681
    K[23] = 0xe7d3fbc8
    K[24] = 0x21e1cde6
    K[25] = 0xc33707d6
    K[26] = 0xf4d50d87
    K[27] = 0x455a14ed
    K[28] = 0xa9e3e905
    K[29] = 0xfcefa3f8
    K[30] = 0x676f02d9
    K[31] = 0x8d2a4c8a
    K[32] = 0xfffa3942
    K[33] = 0x8771f681
    K[34] = 0x6d9d6122
    K[35] = 0xfde5380c
    K[36] = 0xa4beea44
    K[37] = 0x4bdecfa9
    K[38] = 0xf6bb4b60
    K[39] = 0xbebfbc70
    K[40] = 0x289b7ec6
    K[41] = 0xeaa127fa
    K[42] = 0xd4ef3085
    K[43] = 0x04881d05
    K[44] = 0xd9d4d039
    K[45] = 0xe6db99e5
    K[46] = 0x1fa27cf8
    K[47] = 0xc4ac5665
    K[48] = 0xf4292244
    K[49] = 0x432aff97
    K[50] = 0xab9423a7
    K[51] = 0xfc93a039
    K[52] = 0x655b59c3
    K[53] = 0x8f0ccc92
    K[54] = 0xffeff47d
    K[55] = 0x85845dd1
    K[56] = 0x6fa87e4f
    K[57] = 0xfe2ce6e0
    K[58] = 0xa3014314
    K[59] = 0x4e0811a1
    K[60] = 0xf7537e82
    K[61] = 0xbd3af235
    K[62] = 0x2ad7d2bb
    K[63] = 0xeb86d391

fn wrap_u32(value?: int) -> int:
    value & 0xFFffFFff
