#if DEBUG
import Foundation

/// Synthetic data used only by native tests; never opens a user's farm.
enum ExpandedEditorFixture {
    static let item = """
    <Item xsi:type="Object" keep="item"><name>Parsnip</name><itemId>24</itemId><parentSheetIndex>24</parentSheetIndex>
    <stack>0005</stack><quality>00</quality><specialItem>false</specialItem><questItem>false</questItem>
    <isRecipe>false</isRecipe><bigCraftable>false</bigCraftable><modData><keep>unchanged</keep></modData></Item>
    """
    static let chest = """
    <Object xsi:type="Chest" keep="chest"><name>Chest</name><itemId>130</itemId><playerChest>true</playerChest>
    <specialChestType>None</specialChestType><globalInventoryId/><playerChoiceColor><PackedValue>4281545523</PackedValue></playerChoiceColor>
    <items keep="slots">\(item)<Item xsi:nil="true"/><opaque>keep</opaque></items><modData><owner>keep</owner></modData></Object>
    """
    static let machine = """
    <Object xsi:type="Object" keep="machine"><name>Keg</name><itemId>12</itemId><bigCraftable>true</bigCraftable>
    <minutesUntilReady>1200</minutesUntilReady><readyForHarvest>false</readyForHarvest>
    <heldObject xsi:type="Object"><name>Wine</name><itemId>348</itemId><stack>1</stack><quality>0</quality><preservedParentSheetIndex>398</preservedParentSheetIndex></heldObject>
    <modData><flavor>keep</flavor></modData></Object>
    """
    static let xml = """
    <SaveGame xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
    <player><name>小麦</name><farmName>春风农场</farmName><favoriteThing>桂花茶</favoriteThing><UniqueMultiplayerID>42</UniqueMultiplayerID>
    <money>1000</money><maxHealth>100</maxHealth><maxStamina>270</maxStamina><maxItems>12</maxItems>
    <items>\(item)<Item xsi:nil="true"/></items><mailReceived><string>opaqueFlag</string></mailReceived></player>
    <year>2</year><currentSeason>spring</currentSeason><dayOfMonth>12</dayOfMonth><gameVersion>1.6.15</gameVersion>
    <weatherForTomorrow>Rain</weatherForTomorrow><dailyLuck>0.0250</dailyLuck>
    <locationWeather><item><key><string>Default</string></key><value><LocationWeather><weatherForTomorrow>Rain</weatherForTomorrow><isRaining>false</isRaining><keep>weather</keep></LocationWeather></value></item>
    <item><key><string>Island</string></key><value><LocationWeather><weatherForTomorrow>Sun</weatherForTomorrow></LocationWeather></value></item></locationWeather>
    <bundleData><item><key><string>Pantry/0</string></key><value><string>Spring Crops/O 465 20/24 1 0 190 1 0/0/2</string></value></item>
    <item><key><string>Vault/23</string></key><value><string>2,500g/O 220 3/-1 2500 0/4</string></value></item></bundleData>
    <bundles><item><key><int>0</int></key><value><ArrayOfBoolean><boolean>false</boolean><boolean>false</boolean></ArrayOfBoolean></value></item>
    <item><key><int>23</int></key><value><ArrayOfBoolean><boolean>false</boolean></ArrayOfBoolean></value></item></bundles>
    <bundleRewards><item><key><int>0</int></key><value><boolean>false</boolean></value></item></bundleRewards>
    <locations>
    <GameLocation xsi:type="Farm"><name>Farm</name><objects>
    <item><key><Vector2><X>10</X><Y>12</Y></Vector2></key><value>\(chest)</value></item>
    <item><key><Vector2><X>20</X><Y>21</Y></Vector2></key><value>\(machine)</value></item>
    </objects><buildings><Building><buildingType>Shed</buildingType><indoors xsi:type="Shed"><name>Shed_abc</name><objects>
    <item><key><Vector2><X>4</X><Y>5</Y></Vector2></key><value>\(chest)</value></item>
    </objects></indoors></Building></buildings></GameLocation>
    <GameLocation xsi:type="FarmHouse"><name>FarmHouse</name><fridge><Chest><items>\(item)</items><modData><keep>fridge</keep></modData></Chest></fridge>
    <furniture><Item xsi:type="StorageFurniture"><items>\(item)</items></Item></furniture></GameLocation>
    </locations><opaqueWorld keep="yes">unchanged</opaqueWorld></SaveGame>
    """
    static let info = """
    <Farmer><name>小麦</name><farmName>春风农场</farmName><UniqueMultiplayerID>42</UniqueMultiplayerID><money>1000</money><weatherForTomorrow>keep-summary</weatherForTomorrow></Farmer>
    """
}
#endif
