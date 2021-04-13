import std.algorithm;
import std.array;
import std.conv;
import std.exception;
import std.format;
import std.getopt;
import std.random;
import std.regex;
import std.stdint;
import std.stdio;
import std.typecons;

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
 * -1: 持ち駒
 * -2: 駒箱
 */
alias Address = int8_t;

enum Address SQ11 = 0;
enum Address SQ99 = 80;

/**
 * アドレスから筋（1〜9）を返す。
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
 * アドレスから段（1〜9）を返す。
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
enum Color : int8_t
{
    BLACK = 0,  // 先手
    WHITE = 1,  // 後手
}

/**
 * 駒の種類
 */
enum PieceType : int8_t
{
    PAWN = 0, LANCE = 1, KNIGHT = 2, SILVER = 3, GOLD = 4, BISHOP = 5, ROOK = 6, KING = 7,
    PRO_PAWN = 8, PRO_LANCE = 9, PRO_KNIGHT = 10, PRO_SILVER = 11, HORSE = 12, DRAGON = 13,
}

/**
 * 駒の種類の成ってないやつを返す。
 */
PieceType unpromote(PieceType t)
{
    immutable T = [PieceType.PAWN, PieceType.LANCE, PieceType.KNIGHT, PieceType.SILVER, PieceType.GOLD, PieceType.BISHOP, PieceType.ROOK, PieceType.KING,
                   PieceType.PAWN, PieceType.LANCE, PieceType.KNIGHT, PieceType.SILVER, PieceType.BISHOP, PieceType.ROOK];
    return T[t];
}

/**
 * 駒の種類の成ってるやつを返す。
 */
PieceType promote(PieceType t)
{
    immutable T = [PieceType.PRO_PAWN, PieceType.PRO_LANCE, PieceType.PRO_KNIGHT, PieceType.PRO_SILVER, PieceType.GOLD, PieceType.HORSE, PieceType.DRAGON, PieceType.KING,
                   PieceType.PRO_PAWN, PieceType.PRO_LANCE, PieceType.PRO_KNIGHT, PieceType.PRO_SILVER, PieceType.HORSE, PieceType.DRAGON];
    return T[t];
}

/**
 * 駒の種類について成れるかどうかを返す。
 */
bool isPromotable(PieceType t)
{
    //             歩,   香,   桂,   銀,   金,    角,   飛,   玉,    と,    成香,  成桂,  成銀,  馬,    龍
    immutable T = [true, true, true, true, false, true, true, false, false, false, false, false, false, false];
    return T[t];
}

/**
 * 駒（色と種類とアドレスを持つ）
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
    // 0 1  2 3  4 5  6 7  8 9  1011 1213 1415 1617 1819 2021 222324252627282930 313233343536373839
    // 王玉 飛飛 角角 金金 金金 銀銀 銀銀 桂桂 桂桂 香香 香香 歩歩歩歩歩歩歩歩歩 歩歩歩歩歩歩歩歩歩
    Piece[40] pieces;    // 駒が40枚あるはず
    Color sideToMove;    // 手番
    uint64_t boardKey;   // 盤面のハッシュ値
    uint64_t handKey;    // 持ち駒のハッシュ値

    uint64_t key() { return boardKey + handKey; } // 盤面のハッシュ値と持ち駒のハッシュ値を合わせたハッシュ値

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
 *
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
    Address from()   const { return cast(Address)((i >> 7) & 0b01111111); }
    Address to()     const { return cast(Address)(i & 0b01111111); }
    bool isPromote() const { return (i & 0b1000000000000000) != 0; }
    bool isDrop()    const { return (i & 0b0100000000000000) != 0; }
}

// Moveを作る関数
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
 * 局面posにおける指し手mのCSA形式の文字列を返す。例："+7868FU"
 */
string toCsa(Move m, ref Position pos)
{
    if (m == Move.TORYO) return "%TORYO";
    if (m == Move.NULL)  return "Move.NULL";

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

struct Zobrist
{
    static immutable uint64_t[14][2][81] PSQ;
    static immutable uint64_t[8][2] HAND;
    static immutable uint64_t SIDE = 1;

    shared static this() {
        Mt19937_64 rng = Mt19937_64(1070372);
        foreach (ref a; PSQ)  foreach (ref b; a) foreach (ref c; b) rng.popFront(), c = rng.front & ~1UL;
        foreach (ref a; HAND) foreach (ref b; a)                    rng.popFront(), b = rng.front & ~1UL;
    }
}

uint64_t computeBoardKey(ref const Position pos)
{
    uint64_t key = 0;
    foreach (ref p; pos.pieces) if (p.address >= 0)  key ^= Zobrist.PSQ[p.address][p.color][p.type];
    if (pos.sideToMove == Color.WHITE) key ^= Zobrist.SIDE;
    return key;
}

uint64_t computeHandKey(ref const Position pos)
{
    uint64_t key = 0;
    foreach (ref p; pos.pieces) if (p.address == -1) key += Zobrist.HAND[p.color][p.type];
    return key;
}

/**
 * 局面にMoveを適用した新しい局面を作って返す（元の局面は変更しない）。
 */
Position doMove(Position pos, Move m)
{
    // posの中から持ち駒を探して返す
    ref Piece find(ref Position pos, PieceType t) {
        foreach(ref p; pos.pieces) if (p.color == pos.sideToMove && p.type == t && p.address == -1) return p;
        throw new Exception(format("not found %s.", t));
    }

    if (m != Move.TORYO && m != Move.NULL) {
        if (m.isDrop) {
            find(pos, m.type).address = m.to; // 持ち駒を打つ
            pos.handKey -= Zobrist.HAND[pos.sideToMove][m.type];
            pos.boardKey ^= Zobrist.PSQ[m.to][pos.sideToMove][m.type];
        } else {
            Piece* to = pos.lookAt(m.to); // 移動先に駒があるかを見る
            if (to != null) {
                assert(to.color != pos.sideToMove); // 移動先の駒は相手方の駒であること
                pos.boardKey ^= Zobrist.PSQ[to.address][to.color][to.type];
                to.color = pos.sideToMove; // 移動先の駒を自分のものにする
                to.type = to.type.unpromote; // 成っているかもしれないのを戻す
                to.address = -1; // 持ち駒にする
                pos.handKey += Zobrist.HAND[pos.sideToMove][to.type];
            }

            Piece* from = pos.lookAt(m.from); // 移動元の駒について
            pos.boardKey ^= Zobrist.PSQ[from.address][from.color][from.type];
            from.address = m.to; // 移動先に移動させる
            if (m.isPromote) from.type = from.type.promote; // 成るなら成る
            pos.boardKey ^= Zobrist.PSQ[from.address][from.color][from.type];
        }
    }
    pos.sideToMove ^= 1; // 手番を変える
    pos.boardKey ^= Zobrist.SIDE;

    assert(pos.key() == computeBoardKey(pos) + computeHandKey(pos)); // 検算：差分計算したハッシュ値と全計算したハッシュ値が一致すること
    return pos;
}

/**
 * 駒の移動できる方向。NULL終端
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
    if (pos.pieces[0].address < 0 || pos.pieces[1].address < 0) return 0;

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
    if (pos.pieces[0].address < 0 || pos.pieces[1].address < 0) return 0;

    bool[10] pawned = false; // 0～9筋に味方の歩があるか
    bool[81] occupied = false; // 駒があるか
    bool[7]  hand = false; //歩,香,桂,銀,金,角,飛が持駒にあるか
    foreach (ref p; pos.pieces) {
        if (p.address >= 0 && p.color == pos.sideToMove && p.type == PieceType.PAWN) pawned[p.address.file] = true;
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
        for (PieceType t = (pawned[to.file] ? PieceType.LANCE : PieceType.PAWN); t <= PieceType.ROOK ; t++) {
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
Position parsePosition(string sfen)
{
    immutable COLOR_AND_TYPE = [
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
        throw new Exception(format("parsePosition: too many %s in '%s'.", t, sfen));
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

    string[] a = sfen.split(" "); // SFENをスペースで分割する
    string boardState = a[0]; // 盤面
    string sideToMove = a[1]; // 手番
    string piecesInHand = a[2]; // 持ち駒

    // 盤面
    for (int i = 9; i >= 2; i--) boardState = boardState.replace(to!string(i), "1".replicate(i)); // 2～9を1に開いておく
    boardState = boardState.replace("/", "");
    auto m = boardState.matchAll(r"\+?.");
    for (int rank = 0; rank <= 8; rank++) {
        for (int file = 8; file >= 0; file--) {
            string s = m.front.hit;
            if (s != "1") {
                enforce(s in COLOR_AND_TYPE, format("parsePosition: invalid piece '%s' in board state '%s'.", s, boardState)); // COLOR_AND_TYPEになければエラー
                auto t = COLOR_AND_TYPE[s];
                find(pos, t[0], unpromote(t[1])) = Piece(t[0], t[1], cast(Address)(file * 9 + rank));
            }
            m.popFront();
        }
    }

    // 手番
    enforce(sideToMove == "b" || sideToMove == "w", format("parsePosition: invalid side to move: '%s'.", sideToMove)); // 'b'か'w'でなければエラー
    pos.sideToMove = sideToMove == "b" ? Color.BLACK : Color.WHITE;

    // 持ち駒
    if (piecesInHand != "-") {
        // 例：S, 4P, b, 3n, p, 18P
        foreach (c; piecesInHand.matchAll(r"(\d*)(\D)")) {
            int n = c[1] == "" ? 1 : to!int(c[1]);
            enforce(c[2] in COLOR_AND_TYPE, format("parsePosition: invalid piece '%s' in pieces in hand '%s'.", [2], piecesInHand)); // COLOR_AND_TYPEになければエラー
            auto t = COLOR_AND_TYPE[c[2]];
            foreach (_; 0..n)  find(pos, t[0], t[1]) = Piece(t[0], t[1], -1); // 持ち駒はアドレス:-1にしておく
        }
    }

    // ハッシュ
    pos.boardKey = computeBoardKey(pos);
    pos.handKey = computeHandKey(pos);

    return pos;
}

/**
 * SFEN形式の文字列を返す
 */
string toSfen(ref Position pos)
{
    //   歩,  香,  桂,  銀,  金,  角,  飛,  王,   と, 成香, 成桂, 成銀,   馬,   龍,
    immutable SFEN = [
        ["P", "L", "N", "S", "G", "B", "R", "K", "+P", "+L", "+N", "+S", "+B", "+R"],
        ["p", "l", "n", "s", "g", "b", "r", "k", "+p", "+l", "+n", "+s", "+b", "+r"],
    ];

    string hand(ref Position pos, Color color)
    {
        int[7] num; // 0:歩 1:香 2:桂 3:銀 4:金 5:角 6:飛
        foreach (Piece p; pos.pieces) if (p.address == -1 && p.color == color) num[p.type] += 1;
        string s;
        foreach_reverse (i, n; num) {
            if (n > 1) s ~= to!string(n);
            if (n > 0) s ~= SFEN[color][i];
        }
        return s;
    }

    string[] lines;
    for (int rank = 0; rank <= 8; rank++) {
        string l;
        for (int file = 8; file >= 0; file--) {
            Piece* p = pos.lookAt(cast(Address)(file * 9 + rank));
            l ~= p == null ? "1" : SFEN[p.color][p.type];
        }
        lines ~= l;
    }
    string board = lines.join("/");
    for (int i = 9; i >= 2; i--) board = board.replace("1".replicate(i), to!string(i)); // '1'をまとめる
    string side = (pos.sideToMove == Color.BLACK ? "b" : "w");

    // 飛車, 角, 金, 銀, 桂, 香, 歩
    string h = hand(pos, Color.BLACK) ~ hand(pos, Color.WHITE);
    if (h == "") h = "-";
    return format("%s %s %s", board, side, h);
}

/**
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
        foreach (Piece p; pos.pieces) if (p.address == -1 && p.color == color) num[p.type] += 1;
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

int main(string[] args)
{
    Position pos = parsePosition("l6nl/5+P1gk/2np1S3/p1p4Pp/3P2Sp1/1PPb2P1P/P5GS1/R8/LN4bKL w RGgsn5p 1"); // 指し手生成祭り
    //Position pos = parsePosition("lnsgkgsnl/1r5b1/ppppppppp/9/9/9/PPPPPPPPP/1B5R1/LNSGKGSNL b -"); // 平手
    //Position pos = parsePosition("8l/1l+R2P3/p2pBG1pp/kps1p4/Nn1P2G2/P1P1P2PP/1PS6/1KSG3+r1/LN2+p3L w Sbgn3p 124");

    writeln(pos.toSfen());
    writefln("key: %#018x", pos.key());
    writeln(pos.toKi2());

    pos.search();

    writefln("TT_SIZE    : %10,d", TT_SIZE);
    writefln("filled     : %10,d (%3d permille of TT_SIZE)", filled(TT), filled(TT) * 1000 / TT_SIZE);
    writefln("store      : %10,d", STORE);
    writefln("hit        : %10,d (%3d permille of store)",   HIT,        HIT * 1000 / STORE);
    writefln("actual hit : %10,d (%3d permille of hit)",     ACTUAL_HIT, ACTUAL_HIT * 1000 / HIT);
    writefln("miss hit   : %10,d (%3d permille of hit)",     MISS_HIT,   MISS_HIT   * 1000 / HIT);
    return 0;
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

enum TIMES = 1_000_000;
ulong STORE;      // ストアした回数
ulong HIT;        // ヒットした回数（= 正しくヒットした回数 + ミスヒットした回数）
ulong ACTUAL_HIT; // 正しくヒットした回数
ulong MISS_HIT;   // ミスヒットした回数

enum MAX_VALUE = +30000;
enum MIN_VALUE = -30000;

/**
 * 局面を探索する。どこからでも呼べる。
 */
int search(ref Position pos)
{
    int alpha = MIN_VALUE;
    int beta  = MAX_VALUE;

    try {
        for (int depth = 1; ; depth++) {
            _search(pos, depth, alpha, beta);
        }
    }
    catch (Exception e) { }
    return 0;
}

/**
 * 通常探索。その局面の（手番のある側から見た）評価値を返す。_searchから呼ばれる。
 */
int _search(Position pos, int depth, int alpha, int beta)
{
    assert(alpha < beta);

    if (depth <= 0) return eval(pos);

    const uint64_t key = pos.key();
    const uint64_t lookup = TT[key & (TT_SIZE - 1)];
    if (lookup != 0)                  HIT++;        // ヒットした
    if (lookup != 0 && lookup == key) ACTUAL_HIT++; // 正しくヒットした
    if (lookup != 0 && lookup != key) MISS_HIT++;   // ミスヒットした

    Move[593] moves;
    int length = pos.generateMoves(moves);
    if (length == 0) return eval(pos);

    int value = MIN_VALUE;
    foreach (Move move; moves[0..length]) {
        value = max(value, - _search(pos.doMove(move), depth - 1, -beta, -max(alpha, value)));
        if (beta <= value) break;
    }

    TT[key & (TT_SIZE - 1)] = key;
    STORE++;
    if (STORE >= TIMES) throw new Exception("term");

    return value;
}

/**
 * 手番のある側から見た評価値を返す。
 */
int eval(ref Position pos)
{
    //                 歩,   香,   桂,   銀,   金,   角,   飛,     王,   と, 成香, 成桂, 成銀,   馬,    龍,
    immutable SCORE = [90,  315,  405,  495,  540,  855,  990,  15000,  540,  540,  540,  540,  945,  1395];
    int sum = 0;
    foreach (ref p; pos.pieces) sum += (p.color == Color.BLACK ? SCORE[p.type] : -SCORE[p.type]);
    return pos.sideToMove == Color.BLACK ? sum : -sum;
}
