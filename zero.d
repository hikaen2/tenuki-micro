// ldc2 --output-s zero.d -of - -O3 -mcpu=native --boundscheck=off

import std.stdint;
import std.algorithm;
import std.getopt;
import std.socket;
import std.stdio;
import core.time;
import std.regex;
import core.stdc.errno;
import std.format;
import std.typecons;
import std.exception;
import std.array;
import std.conv;

/**
 * アドレス
 *
 *  9  8  7  6  5  4  3  2  1
 * --------------------------+
 * 72 63 54 45 36 27 18  9  0|一
 * 73 64 55 46 37 28 19 10  1|二
 * 74 65 56 47 38 29 20 11  2|三
 * 75 66 57 48 39 30 21 12  3|四
 * 76 67 58 49 40 31 22 13  4|五
 * 77 68 59 50 41 32 23 14  5|六
 * 78 69 60 51 42 33 24 15  6|七
 * 79 70 61 52 43 34 25 16  7|八
 * 80 71 62 53 44 35 26 17  8|九
 *
 * -1: 持駒
 * -2: 駒箱
 */
alias Address = int8_t;

enum Address SQ11 = 0;
enum Address SQ99 = 80;

/**
 * アドレスの筋（1〜9）を返す。
 */
int file(Address a)
{
    immutable T = [
        1, 1, 1, 1, 1, 1, 1, 1, 1,
        2, 2, 2, 2, 2, 2, 2, 2, 2,
        3, 3, 3, 3, 3, 3, 3, 3, 3,
        4, 4, 4, 4, 4, 4, 4, 4, 4,
        5, 5, 5, 5, 5, 5, 5, 5, 5,
        6, 6, 6, 6, 6, 6, 6, 6, 6,
        7, 7, 7, 7, 7, 7, 7, 7, 7,
        8, 8, 8, 8, 8, 8, 8, 8, 8,
        9, 9, 9, 9, 9, 9, 9, 9, 9,
    ];
    return T[a];
}

/**
 * アドレスの段（1〜9）を返す。
 */
int rank(Address a)
{
    immutable T = [
        1, 2, 3, 4, 5, 6, 7, 8, 9,
        1, 2, 3, 4, 5, 6, 7, 8, 9,
        1, 2, 3, 4, 5, 6, 7, 8, 9,
        1, 2, 3, 4, 5, 6, 7, 8, 9,
        1, 2, 3, 4, 5, 6, 7, 8, 9,
        1, 2, 3, 4, 5, 6, 7, 8, 9,
        1, 2, 3, 4, 5, 6, 7, 8, 9,
        1, 2, 3, 4, 5, 6, 7, 8, 9,
        1, 2, 3, 4, 5, 6, 7, 8, 9,
    ];
    return T[a];
}

/**
 * 駒の色
 */
enum Color : uint8_t
{
    BLACK = 0,  // 先手
    WHITE = 1,  // 後手
    NONE  = 2,  // なし
}

/**
 * 駒の種類
 */
enum PieceType : uint8_t
{
    PAWN = 0, LANCE = 1, KNIGHT = 2, SILVER = 3, GOLD = 4, BISHOP = 5, ROOK = 6, KING = 7,
    PRO_PAWN = 8, PRO_LANCE = 9, PRO_KNIGHT = 10, PRO_SILVER = 11, HORSE = 12, DRAGON = 13, EMPTY = 14,
}

/**
 * 駒の種類の成ってないやつを返す。
 */
PieceType unpromote(PieceType t)
{
    immutable T = [PieceType.PAWN, PieceType.LANCE, PieceType.KNIGHT, PieceType.SILVER, PieceType.GOLD, PieceType.BISHOP, PieceType.ROOK, PieceType.KING,
                   PieceType.PAWN, PieceType.LANCE, PieceType.KNIGHT, PieceType.SILVER, PieceType.BISHOP, PieceType.ROOK, PieceType.EMPTY];
    return T[t];
}

/**
 * 駒の種類の成ってるやつを返す。
 */
PieceType promote(PieceType t)
{
    immutable T = [PieceType.PRO_PAWN, PieceType.PRO_LANCE, PieceType.PRO_KNIGHT, PieceType.PRO_SILVER, PieceType.GOLD, PieceType.HORSE, PieceType.DRAGON, PieceType.KING,
                   PieceType.PRO_PAWN, PieceType.PRO_LANCE, PieceType.PRO_KNIGHT, PieceType.PRO_SILVER, PieceType.HORSE, PieceType.DRAGON, PieceType.EMPTY];
    return T[t];
}

/**
 * 駒の種類について成れるかどうかを返す。
 */
bool isPromotable(PieceType t)
{
    immutable T = [true, true, true, true, false, true, true, false, false, false, false, false, false, false, false];
    return T[t];
}

/**
 * 駒（色と型とアドレスを持つ）
 */
struct Piece
{
    Color color;
    PieceType type;
    Address address;
}

/**
 * 局面（40枚の駒と，手番を持つ）
 */
struct Position
{
    Piece[40] pieces; // 駒が40枚あるはず
    Color sideToMove; // 手番

    /**
     * 任意のアドレスにある駒を返す
     */
    Piece* lookAt(Address address)
    {
        foreach(ref p; this.pieces) if (p.address == address) return &p;
        return null; // 見つからなかったらnullを返す
    }
}

/**
 * 指し手
 * 1xxxxxxx xxxxxxxx promote
 * x1xxxxxx xxxxxxxx drop
 * xx111111 1xxxxxxx from
 * xxxxxxxx x1111111 to
 */
struct Move
{
    enum Move NULL      = {0};
    enum Move TORYO     = {0b00111111_11111111};

    uint16_t i;
    PieceType type() const { return cast(PieceType)((i >> 7) & 0b01111111); }
    Address from() const { return cast(Address)((i >> 7) & 0b01111111); }
    Address to() const { return cast(Address)(i & 0b01111111); }
    bool isPromote() const { return (i & 0b1000000000000000) != 0; }
    bool isDrop() const { return (i & 0b0100000000000000) != 0; }
}

// Moveを返す関数
Move createMove(Address from, Address to)        { return Move(cast(uint16_t)(from << 7 | to)); }
Move createMovePromote(Address from, Address to) { return Move(cast(uint16_t)(from << 7 | to | 0b1000000000000000)); }
Move createMoveDrop(PieceType t, Address to)     { return Move(cast(uint16_t)(t << 7 | to | 0b0100000000000000)); }

/**
 * CSA形式の指し手をパースしてMoveを返す。
 */
Move parseMove(string s, ref Position pos)
{
    immutable DIC = [
        "FU": PieceType.PAWN,
        "KY": PieceType.LANCE,
        "KE": PieceType.KNIGHT,
        "GI": PieceType.SILVER,
        "KI": PieceType.GOLD,
        "KA": PieceType.BISHOP,
        "HI": PieceType.ROOK,
        "OU": PieceType.KING,
        "TO": PieceType.PRO_PAWN,
        "NY": PieceType.PRO_LANCE,
        "NK": PieceType.PRO_KNIGHT,
        "NG": PieceType.PRO_SILVER,
        "UM": PieceType.HORSE,
        "RY": PieceType.DRAGON,
    ];

    immutable Address[] ADDRESS = [
         -1, -1, -1, -1, -1, -1, -1, -1, -1, -1,
         -1,  0,  1,  2,  3,  4,  5,  6,  7,  8,
         -1,  9, 10, 11, 12, 13, 14, 15, 16, 17,
         -1, 18, 19, 20, 21, 22, 23, 24, 25, 26,
         -1, 27, 28, 29, 30, 31, 32, 33, 34, 35,
         -1, 36, 37, 38, 39, 40, 41, 42, 43, 44,
         -1, 45, 46, 47, 48, 49, 50, 51, 52, 53,
         -1, 54, 55, 56, 57, 58, 59, 60, 61, 62,
         -1, 63, 64, 65, 66, 67, 68, 69, 70, 71,
         -1, 72, 73, 74, 75, 76, 77, 78, 79, 80,
    ];

    auto m = s.matchFirst(r"(-|\+)(\d{2})(\d{2})(\w{2})");
    Address from = ADDRESS[to!int(m[2])];
    Address to = ADDRESS[to!int(m[3])];
    PieceType t = DIC[m[4]];

    if (from == -1) return createMoveDrop(t, to); // fromが0なら駒打ち
    if (t != pos.lookAt(from).type) return createMovePromote(from, to); // 成る
    return createMove(from, to);
}

/**
 * MoveのCSA形式の文字列を返す
 */
string toCsa(Move m, ref Position pos)
{
    if (m == Move.TORYO) return "%TORYO";

    //                  歩,   香,   桂,   銀,   金,   角,   飛,   玉,   と, 成香, 成桂, 成銀,   馬,   龍,
    immutable CSA   = ["FU", "KY", "KE", "GI", "KI", "KA", "HI", "OU", "TO", "NY", "NK", "NG", "UM", "RY"];
    immutable COLOR = ["+", "-"];
    immutable NUM   = [
        11, 12, 13, 14, 15, 16, 17, 18, 19,
        21, 22, 23, 24, 25, 26, 27, 28, 29,
        31, 32, 33, 34, 35, 36, 37, 38, 39,
        41, 42, 43, 44, 45, 46, 47, 48, 49,
        51, 52, 53, 54, 55, 56, 57, 58, 59,
        61, 62, 63, 64, 65, 66, 67, 68, 69,
        71, 72, 73, 74, 75, 76, 77, 78, 79,
        81, 82, 83, 84, 85, 86, 87, 88, 89,
        91, 92, 93, 94, 95, 96, 97, 98, 99,
    ];

    int from = m.isDrop ? 0 : NUM[m.from];
    int to = NUM[m.to];
    Piece* p = pos.lookAt(m.from);
    PieceType t = m.isDrop ? m.type : m.isPromote ? p.type.promote : p.type;
    return format("%s%02d%02d%s", COLOR[pos.sideToMove], from, to, CSA[t]);
}

/**
 * do_move
 */
Position doMove(Position pos, Move m)
{
    // posの中から持駒を探して返す
    ref Piece find(ref Position pos, PieceType t) {
        foreach(ref p; pos.pieces)  if (p.color == pos.sideToMove && p.type == t && p.address == -1) return p;
        throw new Exception(format("not found %s.", t));
    }

    if (m != Move.TORYO) {
        if (m.isDrop) {
            find(pos, m.type).address = m.to;
        } else {
            Piece* to = pos.lookAt(m.to);
            if (to != null) {
                to.type = to.type.unpromote;
                to.color = pos.sideToMove;
                to.address = -1;
            }

            Piece* from = pos.lookAt(m.from);
            from.address = m.to;
            if (m.isPromote) from.type = from.type.promote;
        }
    }
    pos.sideToMove ^= 1;
    return pos;
}

/**
 * 駒が移動できるところ。NULL終端
 */
immutable Direction[9][14][2] DIRECTIONS = [
    [
        [Direction.N,    Direction.NULL, Direction.NULL, Direction.NULL, Direction.NULL, Direction.NULL, Direction.NULL, Direction.NULL, Direction.NULL], //  0: B_PAWN
        [Direction.FN,   Direction.NULL, Direction.NULL, Direction.NULL, Direction.NULL, Direction.NULL, Direction.NULL, Direction.NULL, Direction.NULL], //  1: B_LANCE
        [Direction.NNE,  Direction.NNW,  Direction.NULL, Direction.NULL, Direction.NULL, Direction.NULL, Direction.NULL, Direction.NULL, Direction.NULL], //  2: B_KNIGHT
        [Direction.N,    Direction.NE,   Direction.NW,   Direction.SE,   Direction.SW,   Direction.NULL, Direction.NULL, Direction.NULL, Direction.NULL], //  3: B_SILVER
        [Direction.N,    Direction.NE,   Direction.NW,   Direction.E,    Direction.W,    Direction.S,    Direction.NULL, Direction.NULL, Direction.NULL], //  4: B_GOLD
        [Direction.FNE,  Direction.FNW,  Direction.FSE,  Direction.FSW,  Direction.NULL, Direction.NULL, Direction.NULL, Direction.NULL, Direction.NULL], //  5: B_BISHOP
        [Direction.FN,   Direction.FE,   Direction.FW,   Direction.FS,   Direction.NULL, Direction.NULL, Direction.NULL, Direction.NULL, Direction.NULL], //  6: B_ROOK
        [Direction.N,    Direction.NE,   Direction.NW,   Direction.E,    Direction.W,    Direction.S,    Direction.SE,   Direction.SW,   Direction.NULL], //  7: B_KING
        [Direction.N,    Direction.NE,   Direction.NW,   Direction.E,    Direction.W,    Direction.S,    Direction.NULL, Direction.NULL, Direction.NULL], //  8: B_PRO_PAWN
        [Direction.N,    Direction.NE,   Direction.NW,   Direction.E,    Direction.W,    Direction.S,    Direction.NULL, Direction.NULL, Direction.NULL], //  9: B_PRO_LANCE
        [Direction.N,    Direction.NE,   Direction.NW,   Direction.E,    Direction.W,    Direction.S,    Direction.NULL, Direction.NULL, Direction.NULL], // 10: B_PRO_KNIGHT
        [Direction.N,    Direction.NE,   Direction.NW,   Direction.E,    Direction.W,    Direction.S,    Direction.NULL, Direction.NULL, Direction.NULL], // 11: B_PRO_SILVER
        [Direction.FNE,  Direction.FNW,  Direction.FSE,  Direction.FSW,  Direction.N,    Direction.E,    Direction.W,    Direction.S,    Direction.NULL], // 12: B_HORSE
        [Direction.FN,   Direction.FE,   Direction.FW,   Direction.FS,   Direction.NE,   Direction.NW,   Direction.SE,   Direction.SW,   Direction.NULL], // 13: B_DRAGON
    ],
    [
        [Direction.S,    Direction.NULL, Direction.NULL, Direction.NULL, Direction.NULL, Direction.NULL, Direction.NULL, Direction.NULL, Direction.NULL], // 14: W_PAWN
        [Direction.FS,   Direction.NULL, Direction.NULL, Direction.NULL, Direction.NULL, Direction.NULL, Direction.NULL, Direction.NULL, Direction.NULL], // 15: W_LANCE
        [Direction.SSW,  Direction.SSE,  Direction.NULL, Direction.NULL, Direction.NULL, Direction.NULL, Direction.NULL, Direction.NULL, Direction.NULL], // 16: W_KNIGHT
        [Direction.S,    Direction.SW,   Direction.SE,   Direction.NW,   Direction.NE,   Direction.NULL, Direction.NULL, Direction.NULL, Direction.NULL], // 17: W_SILVER
        [Direction.S,    Direction.SW,   Direction.SE,   Direction.W,    Direction.E,    Direction.N,    Direction.NULL, Direction.NULL, Direction.NULL], // 18: W_GOLD
        [Direction.FSW,  Direction.FSE,  Direction.FNW,  Direction.FNE,  Direction.NULL, Direction.NULL, Direction.NULL, Direction.NULL, Direction.NULL], // 19: W_BISHOP
        [Direction.FS,   Direction.FW,   Direction.FE,   Direction.FN,   Direction.NULL, Direction.NULL, Direction.NULL, Direction.NULL, Direction.NULL], // 20: W_ROOK
        [Direction.S,    Direction.SW,   Direction.SE,   Direction.W,    Direction.E,    Direction.N,    Direction.NW,   Direction.NE,   Direction.NULL], // 21: W_KING
        [Direction.S,    Direction.SW,   Direction.SE,   Direction.W,    Direction.E,    Direction.N,    Direction.NULL, Direction.NULL, Direction.NULL], // 22: W_PRO_PAWN
        [Direction.S,    Direction.SW,   Direction.SE,   Direction.W,    Direction.E,    Direction.N,    Direction.NULL, Direction.NULL, Direction.NULL], // 23: W_PRO_LANCE
        [Direction.S,    Direction.SW,   Direction.SE,   Direction.W,    Direction.E,    Direction.N,    Direction.NULL, Direction.NULL, Direction.NULL], // 24: W_PRO_KNIGHT
        [Direction.S,    Direction.SW,   Direction.SE,   Direction.W,    Direction.E,    Direction.N,    Direction.NULL, Direction.NULL, Direction.NULL], // 25: W_PRO_SILVER
        [Direction.FSW,  Direction.FSE,  Direction.FNW,  Direction.FNE,  Direction.S,    Direction.W,    Direction.E,    Direction.N,    Direction.NULL], // 26: W_HORSE
        [Direction.FS,   Direction.FW,   Direction.FE,   Direction.FN,   Direction.SW,   Direction.SE,   Direction.NW,   Direction.NE,   Direction.NULL], // 27: W_DRAGON
    ],
];


/**
 * Direction
 * 1111111x value
 * xxxxxxx1 fly
 */
struct Direction {
    enum Direction NULL   = {0};

    enum Direction N   = {-1 * 2}; // -1 << 1
    enum Direction E   = {-9 * 2}; // -9 << 1
    enum Direction W   = {+9 * 2}; // +9 << 1
    enum Direction S   = {+1 * 2}; // +1 << 1
    enum Direction NE  = {N.i + E.i};
    enum Direction NW  = {N.i + W.i};
    enum Direction SE  = {S.i + E.i};
    enum Direction SW  = {S.i + W.i};
    enum Direction NNE = {N.i + N.i + E.i};
    enum Direction NNW = {N.i + N.i + W.i};
    enum Direction SSE = {S.i + S.i + E.i};
    enum Direction SSW = {S.i + S.i + W.i};
    enum Direction FN  = {N.i | 1};
    enum Direction FE  = {E.i | 1};
    enum Direction FW  = {W.i | 1};
    enum Direction FS  = {S.i | 1};
    enum Direction FNE = {NE.i | 1};
    enum Direction FNW = {NW.i | 1};
    enum Direction FSE = {SE.i | 1};
    enum Direction FSW = {SW.i | 1};

    int8_t i;
    bool isFly() const { return (i & 1) != 0; }
    Address  value() const { return i >> 1; }
}

immutable RANK_MIN = [
//  歩,香,桂,銀,金,角,飛,王,と,杏,圭,全,馬,龍
    [2, 2, 3, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1],
    [1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1],
];


immutable RANK_MAX = [
//  歩,香,桂,銀,金,角,飛,王,と,杏,圭,全,馬,龍
    [9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9],
    [8, 8, 7, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9],
];



/**
 * 駒を取る手を生成する
 */
int generateCaptureMoves(ref Position pos, Move[] outMoves)
{
    // if (p.piecesInHand[Color.BLACK][Type.KING] > 0 || p.piecesInHand[Color.WHITE][Type.KING] > 0) {
    //     return 0;
    // }

    bool[81] f_occupied = false;
    bool[81] e_occupied = false;
    foreach (ref p; pos.pieces) {
        if (p.address >= 0 && p.color == pos.sideToMove) f_occupied[p.address] = true; // 味方の駒がいるか
        if (p.address >= 0 && p.color != pos.sideToMove) e_occupied[p.address] = true; // 敵方の駒がいるか
    }

    // 盤上の駒を動かす
    int length = 0;
    foreach (ref p; pos.pieces) {
        if (p.color != pos.sideToMove || p.address < 0) continue;
        for (Direction* d = cast(Direction*)&DIRECTIONS[p.color][p.type][0]; *d != Direction.NULL; d++) {
            for (Address to = cast(Address)(p.address + d.value); !isOverBound(cast(Address)(to - d.value), to) && !f_occupied[to]; to += d.value) {
                if (e_occupied[to]) {
                    if (canPromote(p, p.address, to)) {
                        outMoves[length++] = createMovePromote(p.address, to);
                        if (p.type == PieceType.SILVER || ((to.rank == 3 || to.rank == 7) && (p.type == PieceType.LANCE || p.type == PieceType.KNIGHT))) {
                            outMoves[length++] = createMove(p.address, to); // 銀か, 3段目,7段目の香,桂なら不成も生成する
                        }
                    } else if (RANK_MIN[p.color][p.type] <= to.rank && to.rank <= RANK_MAX[p.color][p.type]) {
                        outMoves[length++] = createMove(p.address, to);
                    }
                    break;
                }
                if (!d.isFly) break; // 飛び駒でなければここでbreak
            }
        }
    }
    return length;
}

/*
 * 合法手生成
 */
int generateMoves(ref Position pos, Move[] outMoves)
{
    // if (p.piecesInHand[Color.BLACK][Type.KING] > 0 || p.piecesInHand[Color.WHITE][Type.KING] > 0) {
    //     return 0;
    // }

    bool[10] pawned = false; // 0～9筋に味方の歩があるか
    bool[81] occupied = false;
    bool[7]  hand = false; //歩,香,桂,銀,金,角,飛が持駒にあるか
    foreach (ref p; pos.pieces) {
        if (p.address >= 0 && p.type == PieceType.PAWN) pawned[p.address.file] = true;
        if (p.address >= 0) occupied[p.address] = true;
        if (p.address == -1 && p.color == pos.sideToMove) hand[p.type] = true;
    }

    // 盤上の駒を動かす
    int length = generateCaptureMoves(pos, outMoves);
    foreach (ref p; pos.pieces) {
        if (p.color != pos.sideToMove || p.address < 0) continue;
        for (Direction* d = cast(Direction*)&DIRECTIONS[p.color][p.type][0]; *d != Direction.NULL; d++) {
            for (Address to = cast(Address)(p.address + d.value); !isOverBound(cast(Address)(to - d.value), to) && !occupied[to]; to += d.value) {
                if (canPromote(p, p.address, to)) {
                    outMoves[length++] = createMovePromote(p.address, to);
                    if (p.type == PieceType.SILVER || ((to.rank == 3 || to.rank == 7) && (p.type == PieceType.LANCE || p.type == PieceType.KNIGHT))) {
                        outMoves[length++] = createMove(p.address, to); // 銀か, 3段目,7段目の香,桂なら不成も生成する
                    }
                } else if (RANK_MIN[p.color][p.type] <= to.rank && to.rank <= RANK_MAX[p.color][p.type]) {
                    outMoves[length++] = createMove(p.address, to);
                }
                if (!d.isFly) break; // 飛び駒でなければここでbreak
            }
        }
    }

    // 持ち駒を打つ
    for (Address to = SQ11; to <= SQ99; to++) {
        if (occupied[to]) continue;
        for (PieceType t = PieceType.ROOK; t >= (pawned[to.file] ? PieceType.LANCE : PieceType.PAWN); t--) { // 飛,角,金,銀,桂,香,歩
            if (hand[t] && to.rank >= RANK_MIN[pos.sideToMove][t] && RANK_MAX[pos.sideToMove][t] >= to.rank) {
                outMoves[length++] = createMoveDrop(t, to);
            }
        }
    }

    return length;
}


bool isOverBound(Address from, Address to)
{
    return to < SQ11 || SQ99 < to || (from.rank == 1 && to.rank == 9) || (from.rank == 9 && to.rank == 1);
}

bool canPromote(ref Piece p, Address from, Address to)
{
    return p.type.isPromotable && (p.color == Color.BLACK ? (from.rank <= 3 || to.rank <= 3) : (from.rank >= 7 || to.rank >= 7));
}







/**
 * SFENをパースして局面を作って返す
 *
 * 例: 8l/1l+R2P3/p2pBG1pp/kps1p4/Nn1P2G2/P1P1P2PP/1PS6/1KSG3+r1/LN2+p3L w Sbgn3p 124
 */
Position parseSfen(string sfen)
{
    immutable COLOR_AND_TYPE = [
        "1":  tuple(Color.NONE,  PieceType.EMPTY),
        "P":  tuple(Color.BLACK, PieceType.PAWN),
        "L":  tuple(Color.BLACK, PieceType.LANCE),
        "N":  tuple(Color.BLACK, PieceType.KNIGHT),
        "S":  tuple(Color.BLACK, PieceType.SILVER),
        "G":  tuple(Color.BLACK, PieceType.GOLD),
        "B":  tuple(Color.BLACK, PieceType.BISHOP),
        "R":  tuple(Color.BLACK, PieceType.ROOK),
        "K":  tuple(Color.BLACK, PieceType.KING),
        "+P": tuple(Color.BLACK, PieceType.PRO_PAWN),
        "+L": tuple(Color.BLACK, PieceType.PRO_LANCE),
        "+N": tuple(Color.BLACK, PieceType.PRO_KNIGHT),
        "+S": tuple(Color.BLACK, PieceType.PRO_SILVER),
        "+B": tuple(Color.BLACK, PieceType.HORSE),
        "+R": tuple(Color.BLACK, PieceType.DRAGON),
        "p":  tuple(Color.WHITE, PieceType.PAWN),
        "l":  tuple(Color.WHITE, PieceType.LANCE),
        "n":  tuple(Color.WHITE, PieceType.KNIGHT),
        "s":  tuple(Color.WHITE, PieceType.SILVER),
        "g":  tuple(Color.WHITE, PieceType.GOLD),
        "b":  tuple(Color.WHITE, PieceType.BISHOP),
        "r":  tuple(Color.WHITE, PieceType.ROOK),
        "k":  tuple(Color.WHITE, PieceType.KING),
        "+p": tuple(Color.WHITE, PieceType.PRO_PAWN),
        "+l": tuple(Color.WHITE, PieceType.PRO_LANCE),
        "+n": tuple(Color.WHITE, PieceType.PRO_KNIGHT),
        "+s": tuple(Color.WHITE, PieceType.PRO_SILVER),
        "+b": tuple(Color.WHITE, PieceType.HORSE),
        "+r": tuple(Color.WHITE, PieceType.DRAGON),
    ];

    ref Piece find(ref Position pos, Color c, PieceType t) {
        foreach(ref p; pos.pieces)  if (p.color == c && p.type == t && p.address == -2) return p;
        foreach(ref p; pos.pieces)  if (p.type == t && p.address == -2)                 return p;
        throw new Exception(format("too many %s in '%s'.", t, sfen));
    }

    Position pos;
    {
        int i = 0;
        foreach (c; [Color.BLACK, Color.WHITE]) foreach (_; 0..1)  pos.pieces[i++] = Piece(c, PieceType.KING, -2);
        foreach (c; [Color.BLACK, Color.WHITE]) foreach (_; 0..1)  pos.pieces[i++] = Piece(c, PieceType.ROOK, -2);
        foreach (c; [Color.BLACK, Color.WHITE]) foreach (_; 0..1)  pos.pieces[i++] = Piece(c, PieceType.BISHOP, -2);
        foreach (c; [Color.BLACK, Color.WHITE]) foreach (_; 0..2)  pos.pieces[i++] = Piece(c, PieceType.GOLD, -2);
        foreach (c; [Color.BLACK, Color.WHITE]) foreach (_; 0..2)  pos.pieces[i++] = Piece(c, PieceType.SILVER, -2);
        foreach (c; [Color.BLACK, Color.WHITE]) foreach (_; 0..2)  pos.pieces[i++] = Piece(c, PieceType.KNIGHT, -2);
        foreach (c; [Color.BLACK, Color.WHITE]) foreach (_; 0..2)  pos.pieces[i++] = Piece(c, PieceType.LANCE, -2);
        foreach (c; [Color.BLACK, Color.WHITE]) foreach (_; 0..9)  pos.pieces[i++] = Piece(c, PieceType.PAWN, -2);
        assert(i == 40);
    }

    string[] a = sfen.split(" ");
    string boardState = a[0];
    string sideToMove = a[1];
    string piecesInHand = a[2];

    // 手番
    enforce(sideToMove == "b" || sideToMove == "w", format("invalid side to move: '%s'.", sideToMove));
    pos.sideToMove = sideToMove == "b" ? Color.BLACK : Color.WHITE;

    // 盤面
    for (int i = 9; i >= 2; i--) {
        boardState = boardState.replace(to!string(i), "1".replicate(i)); // 2～9を1に開いておく
    }
    boardState = boardState.replace("/", "");
    auto m = boardState.matchAll(r"\+?.");
    for (int rank = 0; rank <= 8; rank++) {
        for (int file = 8; file >= 0; file--) {
            auto t = COLOR_AND_TYPE[m.front.hit];
            if (t[1] != PieceType.EMPTY)  find(pos, t[0], unpromote(t[1])) = Piece(t[0], t[1], cast(Address)(file * 9 + rank));
            m.popFront();
        }
    }

    // 持ち駒
    if (piecesInHand != "-") {
        // 例：S, 4P, b, 3n, p, 18P
        foreach (c; piecesInHand.matchAll(r"(\d*)(\D)")) {
            int n = c[1] == "" ? 1 : to!int(c[1]);
            auto t = COLOR_AND_TYPE[c[2]];
            foreach (_; 0..n)  find(pos, t[0], t[1]) = Piece(t[0], t[1], -1); // 持ち駒はアドレス:-1にしておく
        }
    }

    return pos;
}

/*
 * KI2形式の文字列を返す
 */
string toKi2(ref Position pos)
{
    immutable COLOR_STR = [" ", "v"];
    immutable TYPE_STR  = ["歩", "香", "桂", "銀", "金", "角", "飛", "玉", "と", "杏", "圭", "全", "馬", "龍"];
    immutable NUM_STR   = ["〇", "一", "二", "三", "四", "五", "六", "七", "八", "九", "十", "十一", "十二", "十三", "十四", "十五", "十六", "十七", "十八"];

    string hand(ref Position pos, Color color)
    {
        int[7] num; // 0:歩 1:香 2:桂 3:銀 4:金 5:角 6:飛
        foreach (Piece p; pos.pieces) {
            if (p.address == -1 && p.color == color) num[p.type] += 1;
        }
        string s;
        foreach_reverse (i, n; num) {
            if (n > 0) s ~= TYPE_STR[i];
            if (n > 1) s ~= NUM_STR[n];
        }
        if (s.length == 0) s = "なし";
        return s;
    }

    string s;
    s ~= format("後手の持駒：%s\n", hand(pos, Color.WHITE));
    s ~= "  ９ ８ ７ ６ ５ ４ ３ ２ １\n";
    s ~= "+---------------------------+\n";
    for (int rank = 0; rank <= 8; rank++) {
        s ~= "|";
        for (int file = 8; file >= 0; file--) {
            Piece* p = pos.lookAt(cast(Address)(file * 9 + rank));
            s ~= (p == null) ? (" ・") : (COLOR_STR[p.color] ~ TYPE_STR[p.type]);
        }
        s ~= format("|%s\n", NUM_STR[rank + 1]);
    }
    s ~= "+---------------------------+\n";
    s ~= format("先手の持駒：%s\n", hand(pos, Color.BLACK));
    return s;
}





void search(ref Position pos)
{


}






Socket SOCKET;
bool USE_ENHANCED_CSA_PROTOCOL = false;


/**
 * ソケットから１行読み込む
 */
string readLine(ref Socket s)
{
    string line;
    char[1] c;
    for (auto len = s.receive(c); c[0] != '\n'; len = s.receive(c)) {
        if (len == Socket.ERROR) {
            if (errno() == EAGAIN) throw new Exception("recv timed out");
            continue;
        }
        if (len == 0) throw new Exception("connection lost");
        line ~= c;
    }
    writefln("<\"%s\\n\"", line);
    return line;
}

/**
 * ソケットに文字列を書き込む
 */
void writeLine(ref Socket s, string str)
{
    s.send(str ~ "\n");
    writefln(">\"%s\\n\"", str);
}

/**
 * ソケットからパターンに一致するまで行を読む
 */
Captures!string readLineUntil(ref Socket s, string re)
{
    Captures!string m;
    for (string str = s.readLine(); (m = str.matchFirst(re)).empty; str = s.readLine()) {}
    return m;
}


uint64_t get_milliseconds()
{
    import core.sys.linux.time;
    timespec ts;
    //clock_gettime(CLOCK_REALTIME, &ts);
    clock_gettime(CLOCK_REALTIME_COARSE, &ts);
    assert(ts.tv_nsec / 1000000 < 1000);
    return ts.tv_sec * 1000 + ts.tv_nsec / 1000000;
}


int main(string[] args)
{


    for(;;) {
        writeln(get_milliseconds);
    }

    Position pos0 = parseSfen("lnsgkgsnl/1r5b1/ppppppppp/9/9/9/PPPPPPPPP/1B5R1/LNSGKGSNL b -"); // 平手
    writeln(pos0.toKi2());


    Move[100] moves;
    int length = pos0.generateMoves(moves);
    foreach (n; 0..length) writeln(toCsa(moves[n], pos0));

    Move move = createMovePromote(15, 11);
    writeln(move.toCsa(pos0));

    pos0 = pos0.doMove(move);
    writeln(pos0.toKi2());

    return 1;





    uint16_t port = 4081;
    try {
        getopt(args, "e", &USE_ENHANCED_CSA_PROTOCOL, "p", &port);
        if (args.length < 4) throw new Exception("");
    } catch (Exception e) {
        writeln("usage: tenuki [-e] [-p port] hostname username password");
        writeln("  -e  send enhanced CSA protocol");
        writeln("  -p  default: 4081");
        return 1;
    }
    const string hostname = args[1];
    const string username = args[2];
    const string password = args[3];

    stdout.writefln("Connecting to %s port %s.", hostname, port);
    SOCKET = new TcpSocket(new InternetAddress(hostname, port));
    scope(exit) SOCKET.close();
    SOCKET.setOption(SocketOptionLevel.SOCKET, SocketOption.RCVTIMEO, dur!"seconds"(3600));

    SOCKET.writeLine(format("LOGIN %s %s", username, password));
    if (SOCKET.readLine() == "LOGIN:incorrect") return 1;

    string[string] gameSummary;
    for (string line = SOCKET.readLine(); line != "END Game_Summary"; line = SOCKET.readLine()) {
        auto m = line.matchFirst(r"^([^:]+):(.+)$");
        if (!m.empty) gameSummary[m[1]] = m[2];
    }

    const Color us = (gameSummary["Your_Turn"] == "+" ? Color.BLACK : Color.WHITE);
    int timeLeft = to!int(gameSummary["Total_Time"]); // 持ち時間
    const int timeIncrement = to!int(gameSummary["Increment"]); // フィッシャー

    SOCKET.writeLine("AGREE");
    if (!SOCKET.readLine().matchFirst("^START:")) return 1;




    Position pos = parseSfen("lnsgkgsnl/1r5b1/ppppppppp/9/9/9/PPPPPPPPP/1B5R1/LNSGKGSNL b -"); // 平手
    writeln(pos.toKi2());

    if (us == Color.BLACK) {
        timeLeft += timeIncrement;
        search(pos); // search & send
    }

    for (;;) {
        const string line = SOCKET.readLine();
        if (line.matchFirst(r"^(\+|-)\d{4}\D{2},T\d+$")) {

            if (pos.sideToMove == us) timeLeft -= to!int(line.matchFirst(r",T(\d+)")[1]);

            pos = pos.doMove(parseMove(line, pos));
            writeln(pos.toKi2());
            //writeln(search.REMAIN_SECONDS);
            if (pos.sideToMove == us) {
                timeLeft += timeIncrement;
                search(pos); // search & send
            }
        } else if (line.matchFirst(r"^%TORYO(,T\d+)?$") || line.matchFirst(r"^%KACHI(,T\d+)?$")) {
            // do nothing
        } else if (line.among("#ILLEGAL_ACTION", "#ILLEGAL_MOVE", "#JISHOGI", "#MAX_MOVES", "#OUTE_SENNICHITE", "#RESIGN", "#SENNICHITE", "#TIME_UP")) {
            // do nothing
        } else if (line.among("#WIN", "#LOSE", "#DRAW", "#CENSORED", "#CHUDAN")) {
            SOCKET.writeLine("LOGOUT");
            return 0;
        } else if (line == "") {
            // do nothing
        } else {
            writefln("unknown command: '%s'", line);
        }
    }

    return 0;
}



Move ponder(ref Position pos, uint64_t time_end)
{
    // if (pos.inMate()) {
    //     outPv[0] = Move.TORYO;
    //     outPv[1] = Move.NULL;
    //     return -15000;
    // }

    Move bestMove = Move.NULL;
    for (int depth = 1; get_milliseconds() < time_end; depth++) {
        Move move = search0(pos, depth, time_end);
        if (move != Move.NULL) bestMove = move;
    }
    return bestMove;
}



/**
 * ルート局面用のsearch
 */
Move search0(Position pos, int depth, uint64_t time_end)
{
    Move[593] moves;
    int length = pos.generateMoves(moves);
    if (length == 0) return Move.NULL;

    int alpha = short.min;
    int beta = short.max;
    Move bestMove = Move.NULL;
    foreach (Move move; moves[0..length]) {
        int value = -search(pos.doMove(move), depth - 1, -beta, -alpha, time_end);
        if (alpha < value) {
            alpha = value;
            bestMove = move;
        }
    }
    return bestMove;
}

/**
 * 通常探索
 */
int search(Position pos, int depth, int alpha, int beta, uint64_t time_end)
{
    assert(alpha < beta);

    if (get_milliseconds() >= time_end) return beta; // 時間切れ
    if (pos.inUchifuzume) return 15000; // 打ち歩詰めされていれば勝ち
    if (depth <= 0) return qsearch(pos, depth + 4, alpha, beta, time_end); // 静止探索

    Move[593] moves;
    int length = pos.generateMoves(moves);
    if (length == 0) return pos.staticValue;
    foreach (Move move; moves[0..length]) {
        alpha = max(alpha, -search(pos.doMove(move), depth - 1, -beta, -alpha, time_end));
        if (beta <= alpha) return beta;
    }
    return alpha;
}

/**
 * 静止探索
 */
int qsearch(Position pos, int depth, int alpha, int beta, uint64_t time_end)
{
    assert(alpha < beta);

    if (get_milliseconds() >= time_end) return beta; // 時間切れ
    if (depth <= 0) return pos.staticValue;

    alpha = max(alpha, pos.staticValue);
    if (beta <= alpha) return beta;

    Move[593] moves;
    int length = pos.legalCaptureMoves(moves);
    foreach (Move move; moves[0..length]) {
        alpha = max(alpha, -qsearch(pos.doMove(move), depth - 1, -beta, -alpha, time_end));
        if (beta <= alpha) return beta;
    }
    return alpha;
}