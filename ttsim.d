import std.stdint;
import std.random;
import std.stdio;
import std.algorithm.searching;

/**
 * Random Number Generator
 */
Mt19937_64 RNG;
shared static this() { RNG = Mt19937_64(unpredictableSeed); }

/**
 * 64ビット乱数を生成して返す。
 * ただし確率p（千分率）で過去に生成した数を返す。
 */
uint64_t generate(int p)
{
    static uint64_t[] history;
    if (history.length > 0 && p > uniform(0, 1000, RNG)) {
        return history[uniform(0, history.length, RNG)];
    } else {
        history ~= RNG.front;
        RNG.popFront();
        return history[history.length - 1];
    }
}

/**
 * トランスポジションテーブル
 */
enum TT_SIZE = 0xffffff + 1;
uint64_t[TT_SIZE] TT;

ulong filled(uint64_t[] tt)
{
    return tt.count!(n => n != 0);
}

int main()
{
    enum P = 200;     // トランスポジションが発生する確率（千分率）
    ulong store;      // ストアした回数
    ulong hit;        // ヒットした回数（= 正しくヒットした回数 + ミスヒットした回数）
    ulong actual_hit; // 正しくヒットした回数
    ulong miss_hit;   // ミスヒットした回数

    foreach (_; 0..1_000_000) {
        uint64_t key = generate(P);
        uint64_t lookup = TT[key & (TT_SIZE - 1)];
        if (lookup != 0)                  hit++;        // ヒットした
        if (lookup != 0 && lookup == key) actual_hit++; // 正しくヒットした
        if (lookup != 0 && lookup != key) miss_hit++;   // ミスヒットした
        TT[key & (TT_SIZE - 1)] = key;
        store++;
    }

    writefln("P          : %10,d permille", P);
    writefln("TT_SIZE    : %10,d", TT_SIZE);
    writefln("filled     : %10,d (%3d permille of TT_SIZE)", filled(TT), filled(TT) * 1000 / TT_SIZE);
    writefln("store      : %10,d", store);
    writefln("hit        : %10,d (%3d permille of store)",   hit,        hit * 1000 / store);
    writefln("actual hit : %10,d (%3d permille of hit)",     actual_hit, actual_hit * 1000 / hit);
    writefln("miss hit   : %10,d (%3d permille of hit)",     miss_hit,   miss_hit   * 1000 / hit);
    return 0;
}
