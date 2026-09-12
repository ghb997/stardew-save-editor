#if DEBUG
import Foundation

/// Isolated synthetic fixture for the build 15 UI and save regressions.
enum RepairEditorFixture {
    static let axe = """
    <Item xsi:type="Axe"><name>Axe</name><itemId>Axe</itemId><upgradeLevel>1</upgradeLevel>
    <stack>1</stack><quality>0</quality><enchantments/><modData><keep>tool</keep></modData></Item>
    """
    static let weapon = """
    <Item xsi:type="MeleeWeapon"><name>Galaxy Sword</name><itemId>4</itemId><minDamage>60</minDamage>
    <maxDamage>80</maxDamage><speed>4</speed><critChance>0.02</critChance><critMultiplier>3</critMultiplier>
    <enchantments><BaseEnchantment xsi:type="RubyEnchantment"><level>2</level></BaseEnchantment></enchantments></Item>
    """
    static let xml = """
    <SaveGame xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"><player>
    <name>小麦</name><farmName>春风农场</farmName><favoriteThing>桂花茶</favoriteThing>
    <money>1000</money><maxHealth>100</maxHealth><maxStamina>270</maxStamina><maxItems>12</maxItems>
    <items>\(axe)\(weapon)<Item xsi:nil="true"/></items>
    <archaeologyFound><item><key><string>96</string></key><value><ArrayOfInt><int>2</int><int>1</int></ArrayOfInt></value></item></archaeologyFound>
    <fishCaught/><mineralsFound/><basicShipped/></player>
    <year>2</year><currentSeason>spring</currentSeason><dayOfMonth>12</dayOfMonth><gameVersion>1.6.15</gameVersion>
    <locations><GameLocation xsi:type="Farm"><name>Farm</name><objects/></GameLocation>
    <GameLocation xsi:type="LibraryMuseum"><name>ArchaeologyHouse</name><museumPieces>
    <item><key><Vector2><X>26</X><Y>5</Y></Vector2></key><value><string>96</string></value></item>
    </museumPieces></GameLocation></locations></SaveGame>
    """
}
#endif
