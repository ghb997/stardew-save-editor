#if DEBUG
import Foundation

enum DebugDemoSave {
    @MainActor
    static func makeSession(
        itemCatalog: [CatalogItem],
        recipeCatalog: [RecipeKind: [String]]
    ) throws -> SaveSession {
        let data = Data((ProcessInfo.processInfo.arguments.contains("--ui-expanded") ? ExpandedEditorFixture.xml : xml).utf8)
        let pair = SavePairData(main: data, info: nil)
        let parsed = try SaveParser.parse(
            mainData: data,
            infoData: nil,
            catalog: itemCatalog,
            recipeCatalog: recipeCatalog
        )
        let source = SaveSource(
            mode: .twoFiles,
            farmIdentifier: "春风农场_20260820",
            mainURL: URL(fileURLWithPath: "/tmp/春风农场_20260820"),
            infoURL: nil,
            accessURLs: []
        )
        return SaveSession(source: source, parsed: parsed, pair: pair,
                           snapshot: FarmSnapshotExtractor.extract(from: parsed.mainRoot, cropCatalog: try CropCatalog.load()))
    }

    private static let xml = """
    <?xml version="1.0" encoding="utf-8"?>
    <SaveGame xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
      <player>
        <name>小麦</name><farmName>春风农场</farmName><favoriteThing>桂花茶</favoriteThing>
        <money>28640</money><maxHealth>115</maxHealth><maxStamina>338</maxStamina>
        <Gender>Female</Gender><gender>Female</gender><hair>18</hair><skin>2</skin><accessory>4</accessory>
        <hairstyleColor><R>183</R><G>124</G><B>67</B><A>255</A></hairstyleColor>
        <eyeColor><R>66</R><G>132</G><B>123</B><A>255</A></eyeColor>
        <pantsColor><R>83</R><G>100</G><B>163</B><A>255</A></pantsColor>
        <houseUpgradeLevel>2</houseUpgradeLevel>
        <qiGems>18</qiGems><clubCoins>760</clubCoins><totalMoneyEarned>428500</totalMoneyEarned>
        <deepestMineLevel>96</deepestMineLevel>
        <maxItems>12</maxItems>
        <yearForSaveGame>2</yearForSaveGame><seasonForSaveGame>0</seasonForSaveGame><dayOfMonthForSaveGame>12</dayOfMonthForSaveGame>
        <farmingLevel>8</farmingLevel><fishingLevel>6</fishingLevel><foragingLevel>7</foragingLevel><miningLevel>5</miningLevel><combatLevel>4</combatLevel>
        <experiencePoints><int>6900</int><int>3300</int><int>4800</int><int>2150</int><int>1300</int></experiencePoints>
        <professions><int>1</int><int>6</int><int>12</int><int>18</int></professions>
        <mailReceived>
          <string>HasDwarvishTranslationGuide</string><string>HasRustyKey</string>
          <string>HasSkullKey</string><string>HasMagnifyingGlass</string>
        </mailReceived>
        <questLog><Quest/><Quest/><Quest xsi:nil="true"/></questLog>
        <achievements><int>1</int><int>2</int><int>3</int><int>4</int></achievements>
        <basicShipped>
          <item><key><int>24</int></key><value><int>38</int></value></item>
          <item><key><int>188</int></key><value><int>19</int></value></item>
          <item><key><int>190</int></key><value><int>12</int></value></item>
        </basicShipped>
        <fishCaught>
          <item><key><int>128</int></key><value><int>7</int></value></item>
          <item><key><int>129</int></key><value><int>4</int></value></item>
        </fishCaught>
        <mineralsFound><item><key><int>72</int></key><value><int>3</int></value></item></mineralsFound>
        <archaeologyFound><item><key><int>100</int></key><value><int>1</int></value></item></archaeologyFound>
        <secretNotesSeen><int>1</int><int>2</int><int>3</int></secretNotesSeen>
        <eventsSeen><int>10</int><int>20</int><int>30</int><int>40</int><int>50</int></eventsSeen>
        <items>
          <Item xsi:type="Object"><name>Parsnip</name><parentSheetIndex>24</parentSheetIndex><itemId>24</itemId><specialItem>false</specialItem><quality>2</quality><stack>18</stack></Item>
          <Item xsi:type="Object"><name>Stone</name><parentSheetIndex>390</parentSheetIndex><itemId>390</itemId><specialItem>false</specialItem><quality>0</quality><stack>42</stack></Item>
          <Item xsi:type="Object"><name>Diamond</name><parentSheetIndex>72</parentSheetIndex><itemId>72</itemId><specialItem>false</specialItem><quality>0</quality><stack>3</stack></Item>
          <Item xsi:nil="true"/><Item xsi:nil="true"/><Item xsi:nil="true"/>
        </items>
        <friendshipData>
          <item><key><string>Abigail</string></key><value><Friendship><Points>1750</Points><Status>Friendly</Status><GiftsToday>1</GiftsToday><GiftsThisWeek>2</GiftsThisWeek><TalkedToToday>true</TalkedToToday></Friendship></value></item>
          <item><key><string>Robin</string></key><value><Friendship><Points>1250</Points><Status>Friendly</Status></Friendship></value></item>
          <item><key><string>Linus</string></key><value><Friendship><Points>1000</Points><Status>Friendly</Status></Friendship></value></item>
        </friendshipData>
        <cookingRecipes><item><key><string>Fried Egg</string></key><value><int>2</int></value></item></cookingRecipes>
        <craftingRecipes><item><key><string>Chest</string></key><value><int>4</int></value></item></craftingRecipes>
      </player>
      <year>2</year><currentSeason>spring</currentSeason><dayOfMonth>12</dayOfMonth>
      <millisecondsPlayed>68400000</millisecondsPlayed><whichFarm>0</whichFarm><gameVersion>1.6.8</gameVersion>
      <goldenWalnuts>27</goldenWalnuts><mine_lowestLevelReached>100</mine_lowestLevelReached>
      <weatherForTomorrow>rain</weatherForTomorrow><dailyLuck>0.082</dailyLuck>
      <locations>
        <GameLocation xsi:type="FarmHouse">
          <name>FarmHouse</name>
          <appliedWallpaper><SerializableDictionaryOfStringString>
            <item><key><string>FarmHouse</string></key><value><string>7</string></value></item>
            <item><key><string>Bedroom</string></key><value><string>21</string></value></item>
            <item><key><string>Kitchen</string></key><value><string>34</string></value></item>
            <item><key><string>Nursery</string></key><value><string>62</string></value></item>
            <item><key><string>SouthernRoom</string></key><value><string>88</string></value></item>
          </SerializableDictionaryOfStringString></appliedWallpaper>
          <appliedFloor><SerializableDictionaryOfStringString>
            <item><key><string>FarmHouse</string></key><value><string>3</string></value></item>
            <item><key><string>Bedroom</string></key><value><string>11</string></value></item>
            <item><key><string>Kitchen</string></key><value><string>18</string></value></item>
            <item><key><string>Nursery</string></key><value><string>27</string></value></item>
            <item><key><string>SouthernRoom</string></key><value><string>42</string></value></item>
          </SerializableDictionaryOfStringString></appliedFloor>
        </GameLocation>
        <GameLocation xsi:type="Farm">
          <name>Farm</name><piecesOfHay>146</piecesOfHay>
          <objects>
            <item><key><Vector2><X>18</X><Y>20</Y></Vector2></key><value><Object><name>Stone</name><itemId>343</itemId><stack>1</stack></Object></value></item>
            <item><key><Vector2><X>23</X><Y>17</Y></Vector2></key><value><Object><name>Weeds</name><itemId>313</itemId><stack>1</stack></Object></value></item>
            <item><key><Vector2><X>31</X><Y>27</Y></Vector2></key><value><Object><name>Twig</name><itemId>294</itemId><stack>1</stack></Object></value></item>
            <item><key><Vector2><X>42</X><Y>22</Y></Vector2></key><value><Object><name>Chest</name><itemId>130</itemId><stack>1</stack><bigCraftable>true</bigCraftable></Object></value></item>
          </objects>
          <terrainFeatures>
            <item><key><Vector2><X>14</X><Y>29</Y></Vector2></key><value><TerrainFeature xsi:type="HoeDirt"><state>0</state><crop><netSeedIndex>472</netSeedIndex><currentPhase>2</currentPhase><dead>false</dead></crop></TerrainFeature></value></item>
            <item><key><Vector2><X>15</X><Y>29</Y></Vector2></key><value><TerrainFeature xsi:type="HoeDirt"><state>1</state><crop><netSeedIndex>472</netSeedIndex><currentPhase>2</currentPhase><dead>false</dead></crop></TerrainFeature></value></item>
            <item><key><Vector2><X>16</X><Y>29</Y></Vector2></key><value><TerrainFeature xsi:type="HoeDirt"><state>0</state><crop><netSeedIndex>475</netSeedIndex><currentPhase>1</currentPhase><dead>false</dead></crop></TerrainFeature></value></item>
            <item><key><Vector2><X>17</X><Y>29</Y></Vector2></key><value><TerrainFeature xsi:type="HoeDirt"><state>0</state><crop><netSeedIndex>475</netSeedIndex><currentPhase>4</currentPhase><dead>true</dead></crop></TerrainFeature></value></item>
            <item><key><Vector2><X>55</X><Y>18</Y></Vector2></key><value><TerrainFeature xsi:type="Tree"><treeType>1</treeType></TerrainFeature></value></item>
            <item><key><Vector2><X>58</X><Y>19</Y></Vector2></key><value><TerrainFeature xsi:type="FruitTree"><treeId>628</treeId><growthStage>4</growthStage></TerrainFeature></value></item>
          </terrainFeatures>
          <buildings><Building xsi:type="Barn"><buildingType>Deluxe Barn</buildingType><tileX>47</tileX><tileY>10</tileY><daysOfConstructionLeft>0</daysOfConstructionLeft></Building></buildings>
          <animals>
            <item><key><long>1</long></key><value><FarmAnimal>
              <name>奶糖</name><displayName>奶糖</displayName><type>White Cow</type><buildingTypeILiveIn>Deluxe Barn</buildingTypeILiveIn>
              <friendshipTowardFarmer>760</friendshipTowardFarmer><happiness>210</happiness><fullness>190</fullness><daysOwned>84</daysOwned><age>84</age>
              <position><X>3008</X><Y>1728</Y></position>
            </FarmAnimal></value></item>
            <item><key><long>2</long></key><value><FarmAnimal>
              <name>栗子</name><displayName>栗子</displayName><type>Brown Chicken</type><buildingTypeILiveIn>Big Coop</buildingTypeILiveIn>
              <friendshipTowardFarmer>540</friendshipTowardFarmer><happiness>185</happiness><fullness>230</fullness><daysOwned>51</daysOwned><age>51</age>
              <position><X>3264</X><Y>1664</Y></position>
            </FarmAnimal></value></item>
            <item><key><long>3</long></key><value><FarmAnimal>
              <name>团子</name><displayName>团子</displayName><type>Rabbit</type><buildingTypeILiveIn>Big Coop</buildingTypeILiveIn>
              <friendshipTowardFarmer>320</friendshipTowardFarmer><happiness>170</happiness><fullness>205</fullness><daysOwned>30</daysOwned><age>30</age>
              <position><X>3456</X><Y>1792</Y></position>
            </FarmAnimal></value></item>
          </animals>
        </GameLocation>
      </locations>
    </SaveGame>
    """
}
#endif
