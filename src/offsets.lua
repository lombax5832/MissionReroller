-- Every build-specific memory constant of Mission Reroller, for one game
-- build. Nothing else in src/ may hold an address, RVA or struct offset:
-- tests/test_offsets.py fails on one. docs/UPDATING.md is the runbook for a
-- new game build; scripts/check_offsets.py checks this file against a dump.
--
-- code:    game or executable bytes the mod relies on, checked on the first
--          frame. An entry holds its bytes, a size and SHA-256, or names the
--          entry whose bytes contain it (within).
-- globals: module-relative addresses. anchor is an instruction that
--          addresses the global RIP-relative and ends in that displacement
--          ({rva,bytes}), checked on the first frame; tests check that it
--          addresses rva. A global no such instruction reaches says
--          unverified=true.
-- structs: field offsets, strides and sizes of 0x100 or more, relative to
--          the struct named by the table. A field is {value, anchor=...} or
--          {value, unverified=true}. The anchor is the name of a code entry
--          whose bytes use every value as a displacement or immediate (or the
--          first plus multiples of a stride it uses), or one instruction
--          {rva,bytes} whose displacement or immediate is the value; with
--          via='<struct>.<field>' it is the value plus that field's (an
--          offset the compiler folded in), and module='exe' when it is in the
--          executable. Smaller offsets inside a record stay inline.
-- research: RVAs only the Python tools under scripts/ use. The release
--          build leaves this section out.
--
-- from names where a value came from: the Ghidra function (RVA), a doc under
-- docs/, or the script that found it.
return {
build=25480438,
hashes={
    game='2E2C3B7C2500646DADD5F2B4C6E0504DBB7E7896139F64CDDC0D1813C718F51E',
    exe='F5FEE03DCFDB2E553A4752C283590950AC13316B376D8196AA556FF0400D5F06',
},

code={
    -- Seed publication (docs/ONE_SHOT.md): 12d5670 resets the board and
    -- advances the RNG; 12d57e0 publishes the canonical seed and marks the
    -- owner entries dirty.
    campaign_helpers={module='game',rva=0x12d5670,from='12d5670..12d58e0, docs/ONE_SHOT.md',
        bytes='32c04584c974370f57c033c00f1181888e07000f1181988e07000f1181a88e07000f1181b88e07000f1181c88e0700488981d88e07008981e08e0700b00184d2751c83b9848e07000074134584c9750e84c07447ba02000000e912010000488b0563e51a0248ba2d7f954c2df45158480fafc248ba4f8167f77e7b05144803c2ba020000004889053ce51a0248c1e8208981848e0700e9d5000000c3cccccccc458bc84c8d8180720f004881c1109a0f00e94afff0ffccccccccccccccccccccc20000cccccccccccccccccccccccccc488b0599771a02488b0d9a771a0280b8f8020700007448488b0592771a0280b8e6670100007538488b05d20b050280b88d10000000752880b89910000000751f4883b8e808000000751583b998a21700007c0c83b9a4a21700007c03b001c332c0c3cccccccccccccccccccccccccccc48c7c0ffffffff660f1f84000000000048ffc080bc01ec6941000075f34885c00f95c0c3cccccccccccccccccccccccc4057488b0507771a024c8bc18bfa8b88d86201004c8d90e062010085c90f849600000048895c24108bd9488974241833f60f1f40006666660f1f840000000000418b90d0801f0041bbffffffff4d8b0a8bc685d2742266660f1f8400000000008bc84881c108f801004803c94d390cc87449ffc03bc272e8488d8a08f8010048c1e1048d42014903c8418980d0801f004183fbff75060f57c00f110109790c4983c2084c89098971084883eb017591488b742418488b5c24105fc3448bd883f8ff74b58bc84881c108f8010048c1e1044903c8ebc7cccccccccccccccccccccc488b1529761a0241b802000000488b9298b30000e9f7000000cccccccccccccc'},
    publish_seed={module='game',rva=0x12d57e0,within='campaign_helpers',from='12d57e0, called as (board,2); docs/ONE_SHOT.md'},
    -- Operation selection (docs/LIVE_SEARCH_TEST.md, src/ui_operation_selection.lua).
    select_operation={module='game',rva=0x12d1d40,from='12d1d40, the operation-only selection wrapper, called as (0,row)',
        bytes='48894c24084883ec48488b05a0b11a024c8b1591b11a02488b8898b3000049398a78801f007541458b82648e0700448bca418b92608e0700498bca48c744245000000000488b4424504889442438c644243000c744242800000000c7442420ffffffffe848fbffff4883c448c3'},
    select_campaign_row={module='game',rva=0x12d18f0,from='12d18f0, selects the operation with mission=-1',
        bytes='4053565741564883ec58488b05efb51a02448bf2488b9c24b8000000488bf90fb6b424b00000004c8b9098b300004c399178801f00740c32c04883c458415e5f5e5bc3448b916c8e07004889ac24880000008bac24a00000004c89a42490000000448ba1608e07004c89ac2498000000448ba9708e07004c897c2450448bbc24a80000004489b9708e070044899424800000004489b1608e0700448981648e0700448989688e070089a96c8e0700443bd57509453bef0f840301000085ed0f88fb0000004585c90f88f20000004183f96e0f83e8000000418bc1486bc85c80bc39b4720f00000f84d30000008b84399c720f0083f80e731c4869d0a8000000488d05ea7e01024803d07409803a007404b001eb0232c080bfbc8e070000750884c07404b201eb0232d20f10843980720f000f1187888e07000f108c3990720f000f118f988e07000f108439a0720f000f1187a88e07000f108c39b0720f000f118fb88e07000f108439c0720f000f1187c88e0700f20f108c39d0720f00f20f118fd88e07008b8439d8720f008987e08e070084d274298b8fe48e07008d41018987e48e07000fb687bd8e07002c02898f8c8e07003c017607c687bd8e07000183fd007c204183f9007c1a488d97888e0700807a3501750de8a4dcfeff448b94248000000085ed0f883101000089af748e07004088b7788e070048899f7c8e0700453be6750a443bd57505453bef741a83bf6c8e0700007c11c78770801f0000c0a8470fb6b7788e07008b87748e0700f30f1087808e0700f30f108f7c8e0700488b0dbab31a02448b8f688e0700448b87648e07008b97608e0700488b8998b30000f30f11442448f30f114c24404088742438894424308b87708e0700894424288b876c8e070089442420e841718cff0fb687788e070048c7c1fefffffff30f1087808e0700f30f108f7c8e0700448b8f688e0700448b87648e07008b97608e0700f30f11442448f30f114c2440884424388b87748e0700894424308b87708e0700894424288b876c8e070089442420e81cfc90ff4c8b7c2450b0014c8bac24980000004c8ba42490000000488bac24880000004883c458415e5f5e5bc3453be60f84ccfeffffc7442430ffffffff41b9ffffffffc644242801458bc6488bcfc644242000e8d7ba00008987748e07004088b7788e070048899f7c8e0700e9adfeffff'},
    selection_dispatch={module='game',rva=0xb98cc0,from='b98cc0, the event dispatcher of the normal replication path',
        bytes='488bc448895818555657415641574881ec80000000488b3d8ce1780233db418bf1418be8448bf24c8bf9399f206d00000f86b60000004c896008440fb6a424e80000004c896810448bac24e00000000f2970c8f30f10b424f80000000f2978b8'},
    selection_listener={module='game',rva=0x12db270,from='12db270, updates the displayed selection and native UI',
        bytes='4c8bdc535741574881ece00c0000488b058b0d36014833c448898424b00c0000488bf94963d88b8c24280d0000458bf9448b8424300d0000894c24344489442438483b9778801f000f85f90300008b8424200d0000f30f108424480d0000f30f'},
    map_click={module='game',rva=0x148c348,from='148c348, the map click writes the row to [rbx+8] then -1 to [rbx+0xc]',
        bytes='44896308c7430cffffffffe8e859e4ff'},
    -- The generator the Lua port reproduces (docs/LUA_PREDICTION_TEST.md).
    generate_operations={module='game',rva=0x11e3c10,size=1104,sha256='e600b7f917c0dae668397ec326b9ec53df4705e0c1135d5880be8fcaa91d65bd',from='11e3c10, generator'},
    generate_operation_rows={module='game',rva=0x11e4060,size=1136,sha256='5cc7271a512f5caf431abcc5b3e0fcbeb99c325eeae368b03f3ec52427e1661f',from='11e4060, generator'},
    special_events={module='game',rva=0x11e44d0,size=960,sha256='761e9b878f605a026082169dd67c4a2f5cae070d03a840ac2027499531689801',from='11e44d0, special campaign events, src/special_operation_inputs.lua'},
    exclusion_mask={module='game',rva=0x11e4b50,size=248,sha256='0847b63474ce07ef97714cd0acf6d71d76e9a1a4ec1acee82d0d25789bee0dc3',from='11e4b50, the exclusion mask'},
    reseed_board={module='game',rva=0x12d5550,size=288,sha256='b4c826d4744fdbbc161f2da037c544451c77caea400dfe5b87c77233f060289a',from='12d5550, the board wrapper around 11e5670'},
    planet_lookup={module='game',rva=0x12dbd70,size=251,sha256='d8badf0ab4ccd9e8480958210b0e9ead6e36232cebdcddbfe18be4ac30fe5dbd',from='12dbd70, the shared planet lookup: two definition slots, the overflow list, then the third slot'},
    level_choice={module='game',rva=0x11e6020,size=743,sha256='f5570461586131f1cc890d3745194440ae83dd0c2b1bb468db9f947c33fbc848',from='11e6020, src/mission_level_choice.lua'},
    mission_eligibility={module='game',rva=0x11e6800,size=338,sha256='f5dfdd2ba5a53230faa8ad361012721980e49da2a121ad7ad7a44f03d0372358',from='11e6800, src/mission_eligibility.lua'},
    mission_candidates={module='game',rva=0x11e5100,size=1291,sha256='5d9b9f3fb65fd7f0b39817b4919bebea8bd14995f77694053c7f8e0e6aebb488',from='11e5100, candidate eligibility'},
    compose_operation={module='game',rva=0x11e3250,size=2382,sha256='93ef0654c865d859f1299ddcfa11d0c27772ab96542a1d1d95c9c2d819b85e5a',from='11e3250, template and modifier choices, src/composition_prediction.lua'},
    mission_choice={module='game',rva=0x11e6340,size=793,sha256='b417991b06d78e8df61b2866c5373e0b166a018d459dbaa3078f34880d6dfa9f',from='11e6340, src/mission_weighted_choice.lua'},
    enable_rule={module='game',rva=0x11f96e0,size=450,sha256='b121a84355d760e1d95c35e3fbc508a2f86875fe3614cec66b643d4587d03667',from='11f96e0, the enable rule in src/composition_inputs.lua'},
    configuration_tables={module='game',rva=0x12e7990,size=243,sha256='1f2ccbbfa61bc50a3e2ec72bfcc2000a992f09f2495f60be2f173568064de7f4',from='12e7990, src/configuration_lookup.lua'},
    campaign_effects={module='game',rva=0x12df110,size=952,sha256='77111a8319abae6556e658acadbb13660f1582be47b3d2fc5d315ac8232c50a0',from='12df110, src/campaign_effects.lua'},
    template_environments={module='game',rva=0x177e5b0,size=831,sha256='66c3b348db09003218b6cec50fd322fb1de77c4512a464fb135e7556470e28f8',from='177e5b0, src/template_environments.lua'},
    composition_174ab50={module='game',rva=0x174ab50,size=335,sha256='0bd16770e68656de8fb7e84f9d62a64cda0e8ffa0d81c25c539ef4e79d743ab9',from='174ab50, checked by the identity probe since v0.8; role not recorded'},
    composition_174b110={module='game',rva=0x174b110,size=464,sha256='4b395978f97967bfc97024b41ab6b63246c120019aa369f91d358321b543a7a4',from='174b110, checked by the identity probe since v0.8; role not recorded'},
    difficulty_cap={module='game',rva=0x11ebb40,size=152,sha256='5feaccab97b046561f786f2e60533112168f152ebcd19f38ad1e190c9a08e6a9',from='11ebb40, the difficulty cap from configuration'},
    -- The viewed planet's sky, which src/planet_sky.lua reproduces
    -- (docs/DAY_NIGHT_RESEARCH.md).
    sky_time_of_day={module='game',rva=0x1017ef0,size=1725,sha256='4e367c1e600c50d47ee4fb1df5aa4ffb5cc0811b89037c455570d9666eaac286',from='1017ef0, the time of day at a point, src/planet_sky.lua'},
    sky_spin={module='game',rva=0x1016c20,size=865,sha256='7aca46a4a2a862a5b29185365e37d8eca96655ae918040607f22963e329a74b5',from='1016c20, a rotation about Z from war time'},
    sky_orbit={module='game',rva=0x101c7c0,size=5546,sha256='0b2d16d6d90b8aa88fbf5120e61269aa96b0fa7e06eb40746420840b203a4a8e',from='101c7c0, a sky body world transform and its parents'},
    sky_sun={module='game',rva=0x1022270,size=4868,sha256='b8f0bd5e982e6362f4ce46f3669adbe83a874ba59b7dff364634555638b58125',from='1022270, the viewer spin and the direction to the star'},
    rng_scale={module='game',rva=0x23c6780,from='the double 2^-32 the generator RNG scales by, src/generation_rng.lua',
        bytes='000000000000f03d'},
    -- The native window and cursor (docs/MOUSE_INPUT.md, src/window_cursor.lua).
    window_focus_get={module='exe',rva=0x3ff400,from='3ff400, validates a window against the application registry and reads byte +0x89',
        bytes='40534883ec3048894c242033db488d4c2420895c2428885c242ce83176ffff4885c0744a488b0de50d6101488b91c00300008b89b80300004c8d04ca493bd0740e48390274464883c208493bd075f233c984c9488b4c24200f95c38bd3ff158d86ff00b8010000004883c4305bc3488b059b0d61013998b803000074d2488b80c0030000488b004885c074c30fb68889000000ebbccccccccccccccccccccccc488d0559ffffffc3cccccccccccccccc48895c2408574883ec3033ff4889542420488d4c2420897c242840887c242ce87c75ffff488bd84885c074568b542428488b4c2420ffc2ff159b84ff00488b0d1c0d610185c0400f95c7488b81c00300'},
    window_focus_set={module='exe',rva=0x3ff540,from='3ff540, validates the window and stores the focus flag',
        bytes='48895c2408574883ec3048894c242033ff488d4c2420897c242840887c242ce8ec74ffff488bd84885c074568b542428488b4c2420ffc2ff150b84ff00488b0d8c0c610185c0400f95c7488b81c00300008b89b8030000488d14c8483bc2742248391874164883c008483bc275f233c0488b5c24404883c4305fc34088bb89000000488b5c244033c04883c4305fc3cc488d0569ffffffc3cccccccccccccccc4883ec38488d4c24204889542420c744242800000000c644242c00e85074ffff488bd04885c0488b05030c6101742b488b88c00300008b80b80300004c8d04c1493bc8744048391174284883c108493bc875f233c04883c438c383b8b8030000'},
    window_argument={module='exe',rva=0x3f6a50,from='3f6a50, confirms a leading Window userdata argument',
        bytes='48895c2408574883ec208b5908488bf9488b098d5301ff152c1000014885c00f84aa000000488b0f8d5301ff15470e000185c00f8496000000488b0f4c8d05299a2801baf0d8ffffff152a0f0001488b0fbaffffffff448d42ffff15980d0001488b0fbafdffffff8bd8ff15780e000183fb01755a8b5708488b0fffc2ff15c50f0001488b0d36976101488b10ff4708488b81c00300008b89b80300004c8d04c8493bc0740e48391074164883c008493bc075f233c0488b5c24304883c4205fc3488bc2488b5c24304883c4205fc3488b0dea96610133c03981b8030000740a488b81c0030000488b00488b5c24304883c4205fc3cccccccccccccccccccccc'},
    cursor_shown_get={module='exe',rva=0x3ffc20,from='3ffc20, Window.show_cursor getter, reads window+0x88',
        bytes='40534883ec3048894c242033db488d4c2420895c2428885c242ce8116effff4885c0744a488b0dc5056101488b91c00300008b89b80300004c8d04ca493bd0740e48390274464883c208493bd075f233c984c9488b4c24200f95c38bd3ff156d7eff00b8010000004883c4305bc3488b057b0561013998b803000074d2488b80c0030000488b004885c074c30fb68888000000ebbccccccccccccccccccccccc488d0559ffffffc3cccccccccccccccc48895c2420574883ec3033ff4889542420488d4c2420897c242840887c242ce85c6dffff488bd84885c00f84b5000000488b4c242048896c24404c8974244841b6014c897c2450448b7c2428418d5702'},
    cursor_shown_set={module='exe',rva=0x3ffdd0,from='3ffdd0, accepts (window, visible, reposition) and invokes 614e80',
        bytes='48895c2420574883ec3048894c242033ff488d4c2420897c242840887c242ce85c6cffff488bd84885c00f84b5000000488b4c242048896c24404c8974244841b6014c897c2450448b7c2428418d5702ff151a7aff0083f8017515488b4c2420418d5702ff154e7bff0085c0410f95c6488b4c2420418d5701ff15397bff00488b0dba03610185c04c8b7c2450488b6c2440400f95c7488b81c00300008b89b8030000488d14c8483bc274340f1f4000483918741b4883c008483bc275f24c8b74244833c0488b5c24584883c4305fc3450fb6c6400fb6d7488bcbe8d04f21004c8b742448488b5c245833c04883c4305fc3cccccccccccccccccccccccccccc'},
    cursor_apply={module='exe',rva=0x614e80,from='614e80, applies the cursor visibility',
        bytes='48895c2410574883ec30410fb6f8488bd9389188000000746f889188000000488d4c2440ff159624de00488b4b50488d542420ff15df22de0080bb88000000008b4c2424448b44242075198b442440412bc08983800000008b4424442bc18983840000004084ff74178b938400000003d18b8b800000004103c8ff153824de00488bcbe8e8180000488b5c24484883c4305fc3cccccccccccccccccccccccccc40534883ec20488bd948895168e8be180000488b4b504533c94533c0418d51204883c4205b48ff25c424de00cccccccc48895c2410574883ec30488bda488bf9488b4950488d542420ff157923de00f30f2c03488b4f50488d54244089442440'},
    cursor_restore={module='exe',rva=0x6167f0,from='6167f0, restores the existing native cursor',
        bytes='48895c2408574883ec2033ff488bd94038b9040100007404488b797880b98800000000750680794100750d488b79684885ff7504488b7970488bcfff159f0ade00488b4b504c8bc7baf4ffffff488b5c24304883c4205f48ff25a209de00cccc48895c2408574883ec3033ff89513044894134488bd939b948020000763a66908b4334488bd3448b4b3c448b4338894424288b4330448bd749c1e2044c03935002000089442420498b4a0841ff12ffc73bbb4802000072c8488b5c24404883c4305fc3cccccccccccccccccccccccccc48895c240848896c24104889742418574883ec2033db410fb6f00fb6ea488bf939996002000076300f1f840000000000'},
},

globals={
    board={module='game',rva=0x347cee8,anchor={rva=0x11e32ed,bytes='488b0df49b2902'},from='the war-table board pointer, docs/RESEARCH.md'},
    backend={module='game',rva=0x347cee0,anchor={rva=0x12d5740,bytes='488b0599771a02'},from='the backend request owner, src/experiment_adapter.lua snapshot'},
    session={module='game',rva=0x347cef0,anchor={rva=0x12d18fa,bytes='488b05efb51a02'},from='the session and its players, src/experiment_adapter.lua participants'},
    ui_root={module='game',rva=0x3326340,anchor={rva=0x11e514e,bytes='488b05eb111402'},from='the UI root: transition gates and the level controller'},
    screen_owner={module='game',rva=0x347ce28,anchor={rva=0x5c08cb,bytes='488b1556c5eb02'},from='owner of the screen stack, scripts/survey_map_widgets.py'},
    map_ui={module='game',rva=0x3326aa0,anchor={rva=0x51e937,bytes='4c8b0d6281e002'},from='the galactic map UI object, src/map_screen.lua'},
    ui_manager={module='game',rva=0x3326e68,anchor={rva=0xb98cd5,bytes='488b3d8ce17802'},from='the UI manager event registry, scripts/survey_map_widgets.py'},
    objectives={module='game',rva=0x347cf08,anchor={rva=0x72c9d2,bytes='4c8b3d2f05d502'},from='the objective manager, 1267460'},
    global_effects={module='game',rva=0x346d518,anchor={rva=0x8f3647,bytes='488b3dca9eb702'},from='the global event effects, 12e1210 and 11deda0'},
    effect_manager={module='game',rva=0x347cd98,anchor={rva=0x11f9737,bytes='488b0d5a362802'},from='the campaign effect table, 12df110'},
    configuration={module='game',rva=0x347cdf8,anchor={rva=0x11ebba7,bytes='488b0d4a122902'},from='the configuration manager, 7bb8c0 and 12e7990'},
    input_owner={module='game',rva=0x347cf18,anchor={rva=0x5948b9,bytes='488b055886ee02'},from='the input owner, as Mod Bindings Menu v2.0 reads it'},
    rng_state={module='game',rva=0x3483c38,anchor={rva=0x12d56ce,bytes='488b0563e51a02'},from='the RNG 12d5670 advances; must be a private read/write page, docs/ONE_SHOT.md'},
    font={module='game',rva=0x3772268,anchor={rva=0x1388044,bytes='488b3d1da23e02'},from='the font resource the docked panel draws with'},
    font_atlas={module='game',rva=0x3772ee8,anchor={rva=0x1388054,bytes='488b358dae3e02'},from='the font atlas resource'},
    font_material={module='game',rva=0x37c5478,anchor={rva=0x1388030,bytes='488b1d41d44302'},from='the font material owner; its resource hash is at +24'},
    -- Static game data tables.
    environment_tags={module='game',rva=0x21df8d0,anchor={rva=0x177e712,bytes='4c8d1db711a600'},from='ten environment tag hashes, 177e5b0'},
    enemy_tags={module='game',rva=0x21e1920,anchor={rva=0x11dee46,bytes='4c8d2dd32a0001'},from='32 enemy tag hashes, 177dd80'},
    difficulty_rows={module='game',rva=0x328d2a0,anchor={rva=0x11e3511,bytes='488d0d889d0a02'},from='one row per difficulty, 1758000; struct difficulty_row'},
    state_modifiers={module='game',rva=0x32e55e0,anchor={rva=0x6a96e,bytes='48891d6bac2703'},from='world modifiers per planet state, 1267460; struct state_modifiers'},
    operation_modifiers={module='game',rva=0x32e94d0,anchor={rva=0x11e38f5,bytes='488d35d45b1002'},from='thirteen operation modifiers of 0x50 bytes, 11e3250'},
    categories={module='game',rva=0x32e98e0,anchor={rva=0x11e6052,bytes='4c8d3587381002'},from='operation categories of 0xa8 bytes: +8 mission count flag, +9 special'},
    invasion_modifiers={module='game',rva=0x32ef77c,anchor={rva=0x12676f9,bytes='488d057c800802'},from='the world modifier per invasion level, 0x48 bytes apart, 1267460'},
    templates={module='game',rva=0x32fef10,anchor={rva=0x11e328e,bytes='488d357bbc1102'},from='25 operation templates, 11e3250; struct template'},
    mission_types={module='game',rva=0x3773420,anchor={rva=0x11e51f5,bytes='488d1524e25802'},from='162 mission type records, 177deb0; struct mission_type'},
    application={module='exe',rva=0x1a10210,anchor={rva=0x3f6ad3,bytes='488b0d36976101'},from='the Stingray application and its windows, docs/MOUSE_INPUT.md'},
},

structs={
    board={
        selection_context={0x78e60,anchor='select_campaign_row'},
        selected_row={0x78e68,anchor='select_campaign_row'},
        selected_mission={0x78e6c,anchor='select_campaign_row'},
        seed={0x78e84,anchor='campaign_helpers'},
        active_operation={0x78e88,anchor='campaign_helpers'},
        operations={0xf7280,anchor='campaign_helpers'},
        operation_cache={0xf9a08,unverified=true},
        missions={0xf9a10,anchor='campaign_helpers'},
        mission_count={0xffc08,anchor={rva=0x6609bd,bytes='418b9108fc0f00'}},
        mission_cache={0xffc0c,unverified=true},
        campaign={0x101438,anchor='template_environments'},
        -- Three slots that cache planet definitions, keyed by the planet's definition id.
        definitions={0x22b1a8,0x2cc9ec,0x36e230,anchor='planet_lookup'},
        alternate_generation={0x147478,anchor='template_environments'},
        -- Records of 44 bytes: a hash (0x2cb22ffb marks a planet), then the planet.
        world_markers={0x17a09c,anchor={rva=0x11ccf5f,bytes='498d809ca01700'}},
        world_marker_count={0x17a14c,anchor={rva=0x11ccf51,bytes='458b884ca11700'}},
        selection={0x17a298,anchor='campaign_helpers'},
        -- Galactic war time in seconds, a double; copies at 0x46028 and 0x147460.
        war_time={0x1f8058,anchor={rva=0x790b41,bytes='f20f108058801f00'}},
        selection_row={0x17a2a0,anchor={rva=0x6fde4a,bytes='8b82a0a21700'}},
        published_seed={0x17a2bc,unverified=true},
        active_snapshot={0x17a2c0,unverified=true},
        selection_owner={0x1f8078,anchor='select_campaign_row'},
        owners={0x1f8080,unverified=true},
        owner_count={0x1f80d0,anchor='campaign_helpers'},
        world_modifier_values={0x1f88f0,anchor={rva=0xac0dae,bytes='488bbdf0881f00'}},
        world_modifier_ids={0x1f88f8,anchor={rva=0xac0dc8,bytes='4c8b95f8881f00'}},
        world_modifier_count={0x1f8900,anchor={rva=0xac0dba,bytes='448b8500891f00'}},
        special_templates={0x1f8908,anchor='special_events'},
        special_template_ids={0x1f8910,anchor='special_events'},
        special_template_count={0x1f8918,anchor='special_events'},
        planet_overrides={0x1f891c,anchor={rva=0x11cd374,bytes='4439848b1c891f00'}},
        planet_override_count={0x1f897c,anchor={rva=0x11cd35f,bytes='448b9b7c891f00'}},
        mission_preview={0x4168d0,unverified=true},
    },
    -- board+board.campaign. Planet definitions are definition_stride bytes
    -- apart (definition id +0x18, identity key +0x1c, effects +0xb8, count
    -- +0xc8); the planet_* fields are planet_stride bytes apart, and
    -- planet_record is the whole record (faction +0x24, region +0x40).
    campaign={
        definition_stride={0x118,anchor='planet_lookup'},
        planet_count={0x23014,anchor={rva=0x177e5fe,bytes='3bb04c441200',via='board.campaign'}},
        operation_bindings={0x23018,anchor='campaign_effects'},
        operation_binding_count={0x26018,anchor='campaign_effects'},
        planet_stride={0x130,anchor='campaign_effects'},
        planet_record={0x46020,anchor='generate_operation_rows'},
        planet_faction={0x46044,anchor={rva=0xfe807e,bytes='4283bc094460040001'}},
        planet_enabled={0x46050,anchor={rva=0x5bf514,bytes='42389c0988741400',via='board.campaign'}},
        planet_region={0x46060,anchor={rva=0xb958cf,bytes='428b840198741400',via='board.campaign'}},
        planet_effects={0x460e8,anchor='campaign_effects'},
        planet_effect_count={0x46168,anchor='campaign_effects'},
        planet_state={0x46170,anchor={rva=0x72552c,bytes='488d9770610400'}},
        campaign_planet_count={0x6c044,anchor={rva=0x725512,bytes='448b8744c00600'}},
        special_events={0x6c048,anchor='composition_174ab50'},
        special_event_count={0x70048,anchor='composition_174ab50'},
        bases={0x7004c,anchor={rva=0x133ce24,bytes='498d8184141700',via='board.campaign'}},
        base_count={0x7284c,anchor={rva=0x1267ac2,bytes='448b87843c1700',via='board.campaign'}},
        events={0x72c58,anchor='campaign_effects'},
        event_count={0x77a58,anchor='campaign_effects'},
        invasions={0x77a60,anchor='composition_174ab50'},
        invasion_count={0x78c60,anchor='composition_174ab50'},
        planet_effect_lists={0x78c68,anchor='campaign_effects'},
        planet_effect_list_count={0x78d14,anchor='campaign_effects'},
    },
    -- campaign+campaign.events, event bytes apart.
    event={
        size={0x9c0,anchor='campaign_effects'},
        effects={0x920,anchor='campaign_effects'},
        effect_count={0x92c,anchor='campaign_effects'},
        planets={0x930,anchor='campaign_effects'},
        planet_count={0x9b0,anchor='campaign_effects'},
    },
    session={
        local_player={0xb398,anchor='campaign_helpers'},
        player_count={0x162d8,anchor='campaign_helpers'},
        players={0x162e0,anchor='campaign_helpers'},
        gate={0x167e6,anchor='campaign_effects'},
    },
    backend={
        pending_requests={0x31c48,anchor={rva=0x12be6c1,bytes='83be481c030040'}},
        available={0x702f8,anchor='campaign_helpers'},
        state={0x702fc,anchor={rva=0xab0197,bytes='8b80fc020700'}},
    },
    ui_root={
        transition={0x8e8,anchor='campaign_helpers'},
        loading_gate={0x108d,anchor='campaign_effects'},
        transition_gate={0x1099,anchor='campaign_effects'},
        level_controller={0xae288,anchor='mission_candidates'},
    },
    -- ui_root.level_controller: the loaded or previewed level, 177deb0.
    level_controller={
        level={0x2c8,anchor={rva=0x1cfca8,bytes='488b89c8020000'}},
        previous_level={0x288,unverified=true},
        stamp_manager={0x2d0,anchor='mission_candidates'},
    },
    level={
        stamps={0x8996b0,anchor={rva=0x90cd47,bytes='4c8d90b0968900'}},
        stamp_size={0x108,unverified=true},
        kind={0x8bc570,unverified=true},
        explicit_tags={0x8bc654,unverified=true},
        stamp_count={0x11a715c,anchor={rva=0x5d0b46,bytes='458b915c711a01'}},
    },
    -- A stamp record of a stamp set variant; its tag is at +0xd0.
    stamp={
        size={0x1c8,unverified=true},
    },
    -- A biome definition of the level controller's stamp manager, f70f20.
    biome={
        kind={0x2d0,unverified=true},
    },
    -- An environment entry of a biome, environment bytes apart.
    biome_environment={
        size={0x11c,unverified=true},
        weight={0x940,unverified=true},
        id={0x958,unverified=true},
    },
    world_modifier={
        flags={0x110,unverified=true},
    },
    global_effects={
        size={0x164,anchor={rva=0x11def83,bytes='4881c564010000'}},
        count={0x2c80,anchor={rva=0x8f3654,bytes='8b87802c0000'}},
    },
    objectives={
        active={0xfc40,anchor={rva=0x72ca20,bytes='438b843c40fc0000'}},
        entries={0xfc70,anchor={rva=0x126772a,bytes='4c8d9670fc0000'}},
        size={0x7e0,anchor={rva=0x72ca19,bytes='4c69e0e0070000'}},
        entry_rows={0x280,anchor={rva=0x1267731,bytes='458b8a80020000'}},
        count={0x17a40,anchor={rva=0x72c9f7,bytes='4539b7407a0100'}},
    },
    effect_manager={
        count={0xd000,anchor='campaign_effects'},
    },
    configuration={
        -- The primary then the fallback table, 12e7990.
        tables={0x12078,0xc050,anchor='configuration_tables'},
    },
    -- The cached planet definitions, board.definitions: level nodes of 0x88
    -- bytes (kind +0x14, edges +0x18, edge count +0x78), edges of 0x30.
    definitions={
        node_count={0x11004,anchor='level_choice'},
        edges={0x11008,anchor='level_choice'},
        level_roots={0xa100c,anchor='level_choice'},
        special_pool_start={0xa1818,anchor='level_choice'},
        pool_start={0xa1820,anchor='level_choice'},
        special_pool_count={0xa1834,anchor='level_choice'},
        pool_count={0xa183c,anchor='generate_operation_rows'},
    },
    difficulty_row={
        size={0x330,unverified=true},
        missions={0x108,unverified=true},
        budget={0x10c,unverified=true},
        constellation_draws={0x110,unverified=true},
        -- Eight candidates of 12 bytes, then eight blockers, per faction 2 to 4.
        constellation_candidates={0x114,0x174,0x1d4,unverified=true},
        constellation_blockers={0x234,0x258,0x27c,unverified=true},
    },
    state_modifiers={
        size={0x498,anchor={rva=0x1267885,bytes='4869f898040000'}},
    },
    template={
        size={0x490,anchor='compose_operation'},
        modifiers={0x138,anchor='compose_operation'},
        modifier_weights={0x13c,unverified=true},
        rules={0x178,unverified=true},
        rule_count={0x208,unverified=true},
        tag_rows={0x20c,unverified=true},
        tag_row_count={0x48c,unverified=true},
    },
    mission_type={
        size={0x380,anchor='mission_candidates'},
        title_key={0x340,anchor={rva=0x1758a6b,bytes='8b942e40030000'}},
        horde_tag={0x360,anchor={rva=0xad0dda,bytes='488b941160030000'}},
        biomes={0x368,unverified=true},
        biome_count={0x370,unverified=true},
    },
    map_ui={
        planet={0x4ef8,anchor={rva=0x6618e1,bytes='48c781f84e0000ffffffff'}},
        -- The viewed planet's sky (725160 runs 1023d70 on it): its seed, the
        -- settings (quaternion +0xc, viewer body +0x2c) and the environment.
        sky_seed={0x23b0,anchor='sky_orbit'},
        sky_settings={0x24d0,unverified=true},
        sky={0x2530,anchor={rva=0x142af79,bytes='0fb68730250000'}},
        rows={0x4f00,anchor={rva=0x6618ec,bytes='48c781004f0000ffffffff'}},
        difficulty={0x4f14,anchor={rva=0x724070,bytes='8b80144f0000'}},
        processed_row={0x4f98,unverified=true},
    },
    -- A body of a sky, size bytes apart from the environment's start
    -- (quaternions +0x94 and +0xa4); periods, phase and blends in 101c7c0
    -- and 1022270.
    sky_body={
        size={0x1c0,anchor='sky_orbit'},
        parent={0x171,anchor='sky_orbit'},
        distance={0x174,anchor='sky_orbit'},
        orbit_period={0x188,anchor='sky_orbit'},
        spin_period={0x190,anchor='sky_sun'},
        phase={0x1b4,anchor='sky_orbit'},
        orbit_blend={0x1c0,anchor='sky_orbit'},
        spin_blend={0x1c4,anchor='sky_sun'},
    },
    screen_owner={
        stack={0x429c,anchor={rva=0x5c08e0,bytes='488d829c420000'}},
    },
    ui_manager={
        -- The map screen's subscriber entry, scripts/survey_map_widgets.py.
        registry={0x6288,anchor={rva=0xb2a7a0,bytes='8b8188620000'}},
    },
    map_screen={
        -- The BACK hint widget record, scripts/survey_map_widgets.py on 2026-09-29.
        hint_widget={0x6a0,unverified=true},
    },
    input_owner={
        binding_map={0xa7ad0,anchor={rva=0x6c7684,bytes='488b98d07a0a00'}},
        bucket={0x148,unverified=true},
    },
    application={
        window_count={0x3b8,anchor='window_argument'},
        windows={0x3c0,anchor='window_argument'},
    },
},

research={
    -- Functions the Unicorn validators call or replace. The generator code
    -- they emulate is listed under code (compose_operation, level_choice, ...).
    generate_missions={rva=0x11e5670,from='11e5670, the mission generator scripts/emulate_seed.py replays after 12d5550'},
    template_candidates={rva=0x11e4cd0,from='11e4cd0, the template candidate collector validate_composition_choices.py replaces'},
    composition_174a610={rva=0x174a610,from='174a610, stubbed to return 0 by validate_composition_choices.py'},
    composition_174a6e0={rva=0x174a6e0,from='174a6e0, stubbed to return 0 by validate_composition_choices.py'},
    -- Code pages the validators map executable ({rva,size}).
    code_section={rva=0x1000,size=0x210f000,from='the first section of game.dll, dumps/build-25480438/inspection.txt'},
    generator_pages={rva=0x11e3000,size=0x4000,from='11e3000..11e7000, the composition generator, validate_composition_choices.py'},
    choice_pages={rva=0x11e6000,size=0x1000,from='11e6000..11e7000, level and mission choice, validate_level_choice.py'},
    helper_pages={rva=0x2088000,size=0x1000,from='2088000..2089000, a code page the generator calls into'},
},
}
