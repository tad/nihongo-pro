//  Learner keywords and display glyphs for the KRADFILE components.
//
//  Hand-authored to match the register `kanjiInfoSystemPrompt` already uses for
//  `KanjiInfo.components` ("尸 flag", "亻 person", "穴 hole"): the character,
//  a space, one or two lowercase words. Every component appearing in
//  krad_decompositions.json has an entry here.
//
//  MIRRORED with the kanji-study app's `KradKeywords.swift` — the two files are
//  byte-identical apart from this header. That app has a test target whose
//  `KradTests.everyComponentHasAKeyword` enforces the completeness invariant;
//  this app has no test target, so if the KRAD data is ever regenerated, verify
//  it over there and copy both files across together.

enum KradKeywords {
    /// Keyed by the raw KRADFILE component character (the stand-in, where the
    /// data uses one), so the two 阝 forms keep distinct keywords.
    static let keywords: [String: String] = [
        "口": "mouth", "一": "one", "ノ": "slash", "｜": "stick", "日": "sun", "木": "tree", "ハ": "eight",
        "二": "two", "丶": "drop", "土": "earth", "十": "ten", "田": "rice field", "艾": "grass", "目": "eye",
        "并": "horns", "亠": "lid", "冂": "open box", "大": "big", "小": "small", "月": "moon", "汁": "water",
        "儿": "legs", "杰": "fire", "勹": "wrap", "化": "person", "厶": "private", "个": "person top",
        "幺": "tiny thread", "冖": "cover", "人": "person", "又": "again", "匕": "spoon", "王": "king",
        "金": "gold", "扎": "hand", "貝": "shell", "宀": "roof", "厂": "cliff", "虫": "insect",
        "糸": "thread", "乞": "hat", "女": "woman", "亅": "hook", "言": "speech", "止": "stop", "立": "stand",
        "心": "heart", "山": "mountain", "乙": "fishhook", "ヨ": "broom", "尸": "flag", "廾": "two hands",
        "卜": "fortune", "夂": "winter", "戈": "halberd", "忙": "heart", "冫": "ice", "禾": "grain",
        "隹": "small bird", "竹": "bamboo", "火": "fire", "込": "road", "广": "canopy", "寸": "inch",
        "米": "rice", "凵": "container", "攵": "strike", "几": "table", "買": "net", "魚": "fish",
        "刀": "sword", "士": "samurai", "鳥": "bird", "白": "white", "刈": "sword", "囗": "enclosure",
        "石": "stone", "巾": "cloth", "車": "car", "爪": "claw", "匚": "box", "力": "power", "彡": "bristles",
        "工": "work", "皿": "dish", "尚": "small crown", "夕": "evening", "衣": "clothes", "足": "foot",
        "疔": "sickness", "弓": "bow", "邦": "city", "子": "child", "干": "dry", "曰": "say", "已": "already",
        "豆": "bean", "阡": "hill", "耳": "ear", "門": "gate", "卩": "seal", "方": "direction", "馬": "horse",
        "水": "water", "彳": "step", "斤": "axe", "臼": "mortar", "初": "clothes", "頁": "head",
        "犯": "beast", "雨": "rain", "比": "compare", "羽": "feathers", "羊": "sheep", "酉": "sake jar",
        "虍": "tiger", "豕": "pig", "里": "village", "欠": "yawn", "マ": "katakana ma", "殳": "weapon",
        "氏": "clan", "牛": "cow", "矢": "arrow", "西": "west", "示": "altar", "革": "leather",
        "艮": "stubborn", "甘": "sweet", "勿": "must not", "老": "old", "自": "self", "辛": "spicy",
        "疋": "cloth bolt", "爿": "bed", "礼": "altar", "戸": "door", "見": "see", "長": "long",
        "臣": "minister", "犬": "dog", "巛": "flowing river", "九": "nine", "用": "use", "矛": "spear",
        "舟": "boat", "歹": "bare bone", "而": "whiskers", "支": "branch", "冊": "book", "禹": "track",
        "弋": "stake", "鹿": "deer", "巴": "swirl", "手": "hand", "音": "sound", "穴": "hole",
        "髟": "long hair", "聿": "brush", "食": "eat", "入": "enter", "屮": "sprout", "缶": "jar",
        "至": "arrive", "非": "wrong", "ユ": "katakana yu", "生": "life", "角": "horn", "元": "origin",
        "乃": "from", "廴": "stretch", "玄": "mysterious", "骨": "bone", "尢": "lame", "父": "father",
        "走": "run", "爻": "crossing", "辰": "dragon", "鬼": "demon", "黒": "black", "世": "generation",
        "川": "river", "舛": "opposing feet", "亡": "death", "歯": "tooth", "韋": "tanned leather",
        "也": "also", "文": "writing", "毋": "do not", "母": "mother", "癶": "footsteps", "行": "go",
        "高": "tall", "舌": "tongue", "谷": "valley", "釆": "separate", "片": "one-sided", "牙": "fang",
        "青": "blue", "豸": "badger", "風": "wind", "黄": "yellow", "彑": "snout", "身": "body",
        "品": "goods", "斗": "dipper", "耒": "plow", "五": "five", "免": "exempt", "瓜": "melon",
        "屯": "barracks", "皮": "skin", "隶": "capture", "鬲": "cauldron", "井": "well", "无": "without",
        "赤": "red", "麻": "hemp", "竜": "dragon", "鼠": "rat", "尤": "especially", "毛": "fur", "瓦": "tile",
        "齊": "old alignment", "及": "reach", "气": "steam", "鼻": "nose", "奄": "suddenly", "血": "blood",
        "無": "nothing", "韭": "leek", "色": "color", "滴": "stem", "面": "face", "首": "neck", "黽": "frog",
        "龠": "flute", "鼓": "drum", "肉": "meat", "亀": "turtle", "巨": "giant", "鹵": "salt",
        "久": "long time", "岡": "ridge", "鬥": "fight", "斉": "alignment", "黍": "millet", "鼎": "tripod",
        "香": "fragrance", "麦": "wheat", "黹": "embroidery", "飛": "fly", "鬯": "sacrificial wine"
    ]

    /// KRADFILE draws its components from JIS X 0208, which lacks many radical
    /// forms, so it substitutes a kanji that contains the element — 汁 for 氵,
    /// 艾 for 艹, 邦/阡 for the right/left 阝. Displaying the stand-in would show
    /// (and tell Claude to write) a character that is not in the glyph at all,
    /// which is exactly the mnemonic failure the system prompt warns against.
    /// Mapping from the table in EDRDG's `kradintro`; targets are the standard
    /// codepoints rather than the CJK Radicals Supplement forms, which render
    /// inconsistently.
    static let displayGlyphs: [String: String] = [
        "化": "亻", "个": "𠆢", "并": "丷", "刈": "刂", "込": "辶", "尚": "⺌", "忙": "忄", "扎": "扌", "汁": "氵",
        "犯": "犭", "艾": "艹", "邦": "阝", "阡": "阝", "老": "耂", "杰": "灬", "礼": "礻", "疔": "疒", "禹": "禸",
        "初": "衤", "買": "罒", "滴": "啇", "乞": "𠂉"
    ]
}
