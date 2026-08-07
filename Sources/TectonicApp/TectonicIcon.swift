import SwiftUI
import CoreText
import AppKit

// MARK: - Tabler Icons 字体集成（开源线性图标集，MIT License）

/// 图标枚举：case 名 -> Tabler Unicode 码点
enum TectonicIcon: String, CaseIterable {
    case activity = "\u{ED23}"
    case adjustments = "\u{EA03}"
    case alertTriangle = "\u{EA06}"
    case arrowDown = "\u{EA16}"
    case arrowUp = "\u{EA25}"
    case arrowsLeftRight = "\u{EDB0}"
    case arrowsMove = "\u{F22F}"
    case arrowsSort = "\u{EB5A}"
    case arrowsUpDown = "\u{EDB6}"
    case award = "\u{EA2C}"
    case bell = "\u{EA35}"
    case bolt = "\u{EA38}"
    case bookmark = "\u{EA3A}"
    case borderAll = "\u{EA3B}"
    case box = "\u{EA45}"
    case braces = "\u{EBCC}"
    case briefcase = "\u{EA46}"
    case brush = "\u{EBB8}"
    case building = "\u{EA4F}"
    case buildingBank = "\u{EBE2}"
    case buildingCommunity = "\u{EBF6}"
    case buildingSkyscraper = "\u{EC39}"
    case bulb = "\u{EA51}"
    case calculator = "\u{EB80}"
    case calendar = "\u{EA53}"
    case calendarEvent = "\u{EA52}"
    case calendarPlus = "\u{EBBA}"
    case calendarStats = "\u{EE20}"
    case calendarTime = "\u{EE21}"
    case candle = "\u{EFC6}"
    case chartArea = "\u{EA58}"
    case chartBar = "\u{EA59}"
    case chartDonut = "\u{EA5B}"
    case chartDots = "\u{EE2F}"
    case chartLine = "\u{EA5C}"
    case chartPie = "\u{EA5D}"
    case check = "\u{EA5E}"
    case chevronDown = "\u{EA5F}"
    case chevronLeft = "\u{EA60}"
    case chevronRight = "\u{EA61}"
    case circle = "\u{EA6B}"
    case circleCheck = "\u{EA67}"
    case circleHalf = "\u{EE3F}"
    case circlePlus = "\u{EA69}"
    case circleX = "\u{EA6A}"
    case clock = "\u{EA70}"
    case clock2 = "\u{F099}"
    case clockExclamation = "\u{F847}"
    case cloud = "\u{EA76}"
    case code = "\u{EA77}"
    case coin = "\u{EB82}"
    case coins = "\u{F65D}"
    case columns = "\u{EB83}"
    case crown = "\u{ED12}"
    case cube = "\u{FA97}"
    case currencyBitcoin = "\u{EBAB}"
    case currencyDollar = "\u{EB84}"
    case currencyYen = "\u{EBAE}"
    case currentLocation = "\u{ECEF}"
    case dashboard = "\u{EA87}"
    case database = "\u{EA88}"
    case dots = "\u{EA95}"
    case download = "\u{EA96}"
    case edit = "\u{EA98}"
    case externalLink = "\u{EA99}"
    case eye = "\u{EA9A}"
    case fileText = "\u{EAA2}"
    case filter = "\u{EAA5}"
    case flag = "\u{EAA6}"
    case flame = "\u{EC2C}"
    case folder = "\u{EAAD}"
    case gauge = "\u{EAB1}"
    case gitBranch = "\u{EAB2}"
    case globe = "\u{EAB9}"
    case hash = "\u{EABC}"
    case heart = "\u{EABE}"
    case help = "\u{EABF}"
    case history = "\u{EBEA}"
    case home = "\u{EAC1}"
    case inbox = "\u{EAC4}"
    case infoCircle = "\u{EAC5}"
    case key = "\u{EAC7}"
    case lamp = "\u{EFAB}"
    case language = "\u{EBBE}"
    case layoutGrid = "\u{EDBA}"
    case layoutList = "\u{EC14}"
    case link = "\u{EADE}"
    case list = "\u{EB6B}"
    case listCheck = "\u{EB6A}"
    case lock = "\u{EAE2}"
    case lockOpen = "\u{EAE1}"
    case mail = "\u{EAE5}"
    case mapPin = "\u{EAE8}"
    case maximize = "\u{EAEA}"
    case menu = "\u{EAEB}"
    case menu2 = "\u{EC42}"
    case minimize = "\u{EAF1}"
    case moon = "\u{EAF8}"
    case mountain = "\u{EF97}"
    case news = "\u{EAFD}"
    case package = "\u{EAFF}"
    case paint = "\u{EB00}"
    case palette = "\u{EB01}"
    case pencil = "\u{EB04}"
    case percentage = "\u{ECF4}"
    case phone = "\u{EB09}"
    case pin = "\u{EC9C}"
    case plus = "\u{EB0B}"
    case point = "\u{EB0C}"
    case pointFilled = "\u{F698}"
    case questionMark = "\u{EC9D}"
    case quote = "\u{EFBE}"
    case receipt = "\u{EDFD}"
    case refresh = "\u{EB13}"
    case robot = "\u{F00B}"
    case scale = "\u{EBC2}"
    case search = "\u{EB1C}"
    case searchOff = "\u{F19C}"
    case send = "\u{EB1E}"
    case settings = "\u{EB20}"
    case share = "\u{EB21}"
    case shieldCheck = "\u{EB22}"
    case sparkles = "\u{F6D7}"
    case square = "\u{EB2C}"
    case stack = "\u{EB2D}"
    case star = "\u{EB2E}"
    case starFilled = "\u{F6A6}"
    case sun = "\u{EB30}"
    case tag = "\u{10096}"
    case target = "\u{EB35}"
    case terminal2 = "\u{EBEF}"
    case toggleLeft = "\u{EB3E}"
    case toggleRight = "\u{EB3F}"
    case trash = "\u{EB41}"
    case trendingDown = "\u{EB42}"
    case trendingUp = "\u{EB43}"
    case wallet = "\u{EB75}"
    case waveSine = "\u{ECD4}"
    case wifiOff = "\u{ECFA}"
    case world = "\u{EB54}"
    case x = "\u{EB55}"
    case zoomIn = "\u{EB56}"
    case zoomOut = "\u{EB57}"
}

extension TectonicIcon {
    /// 注册 Tabler 字体（App 启动时调用一次）
    @discardableResult
    static func registerFont() -> Bool {
        guard let url = Bundle.main.url(forResource: "tabler-icons", withExtension: "ttf") else {
            print("TectonicIcon: tabler-icons.ttf not found in bundle")
            return false
        }
        var error: Unmanaged<CFError>?
        let registered = CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error)
        if registered {
            print("TectonicIcon: Tabler icons registered")
            return true
        }
        if let err = error?.takeRetainedValue() {
            let ns = err as Error as NSError
            if ns.code == 105 { return true } // 已注册视为成功
            print("TectonicIcon: registration failed \(ns)")
        } else {
            print("TectonicIcon: registration failed (unknown)")
        }
        return false
    }
}

/// 图标视图：用 Tabler 字体渲染，尺寸/颜色可调
struct TectonicIconView: View {
    let icon: TectonicIcon
    var size: CGFloat = 16
    var color: Color = .primary

    var body: some View {
        Text(icon.rawValue)
            .font(.custom("tabler-icons", size: size))
            .foregroundStyle(color)
            .frame(width: size + 2, height: size + 2)
            .accessibilityHidden(true)
    }
}