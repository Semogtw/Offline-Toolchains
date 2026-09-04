extends Control

const W := 1080.0
const CONTENT_TOP := 170.0
const CONTENT_BOTTOM := 2255.0
const INK := Color("f7f2e6")
const MUTED := Color("a8bdca")
const GOLD := Color("f5ca64")
const CYAN := Color("63d9e8")
const GREEN := Color("70d493")
const VIOLET := Color("b779ff")
const ORANGE := Color("f0a45d")
const RED := Color("ef6d7a")

var host
var profile
var db
var screen_name: String = "home"
var anim_time: float = 0.0
var reduced_motion: bool = false
var high_contrast: bool = false

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(true)
	visible = true

func _process(delta: float) -> void:
	host = get_parent()
	if host == null:
		visible = false
		return
	screen_name = str(host.get("current_screen"))
	visible = screen_name != "battle"
	if not visible:
		return
	profile = host.get("profile")
	db = host.get("db")
	if profile != null:
		configure_accessibility(profile.settings)
	if not reduced_motion:
		anim_time += delta
	queue_redraw()

func configure_accessibility(settings: Dictionary) -> void:
	reduced_motion = bool(settings.get("reduced_motion", false))
	high_contrast = bool(settings.get("high_contrast", false))

func screen_theme(name: String) -> Dictionary:
	match name:
		"home": return {"accent": CYAN, "secondary": GOLD, "mood": "astral", "pattern": "constellation", "base": Color("0e2130")}
		"collection": return {"accent": VIOLET, "secondary": CYAN, "mood": "archive", "pattern": "hexgrid", "base": Color("171b31")}
		"decks": return {"accent": Color("65a7ff"), "secondary": ORANGE, "mood": "tactical", "pattern": "chevrons", "base": Color("101f31")}
		"missions": return {"accent": GREEN, "secondary": GOLD, "mood": "expedition", "pattern": "tracks", "base": Color("10281f")}
		"vaults": return {"accent": GOLD, "secondary": CYAN, "mood": "reliquary", "pattern": "runes", "base": Color("282317")}
		"exchange": return {"accent": VIOLET, "secondary": ORANGE, "mood": "forge", "pattern": "circuits", "base": Color("25172c")}
		"profile": return {"accent": CYAN, "secondary": Color("7ba6ff"), "mood": "sanctum", "pattern": "rings", "base": Color("112231")}
		_: return {"accent": CYAN, "secondary": GOLD, "mood": "neutral", "pattern": "stars", "base": Color("101826")}

func card_style(card_id: String, db_ref) -> Dictionary:
	var card: Dictionary = {}
	if db_ref != null and db_ref.cards.has(card_id):
		card = db_ref.cards[card_id]
	var family: String = str(card.get("family", "troop"))
	var rarity: String = str(card.get("rarity", "common"))
	var family_mark: String = "blade"
	if family == "structure": family_mark = "tower"
	elif family == "spell": family_mark = "rune"
	var rarity_mark: String = rarity.to_lower()
	var accent: Color = _card_accent(card_id)
	var frame: Color = Color("25364a")
	match rarity_mark:
		"rare": frame = Color("244d59")
		"epic": frame = Color("4b3464")
		"legendary": frame = Color("695127")
	return {"accent": accent, "frame": frame, "family_mark": family_mark, "rarity_mark": rarity_mark}

func presentation_snapshot() -> Dictionary:
	var theme: Dictionary = screen_theme(screen_name)
	return {"screen":screen_name,"mood":str(theme.mood),"pattern":str(theme.pattern),"reduced_motion":reduced_motion,"high_contrast":high_contrast,"time":anim_time}

func _draw() -> void:
	if not visible: return
	var theme: Dictionary = screen_theme(screen_name)
	_draw_background(theme)
	match screen_name:
		"home": _draw_home(theme)
		"collection": _draw_collection(theme)
		"decks": _draw_decks(theme)
		"missions": _draw_missions(theme)
		"vaults": _draw_vaults(theme)
		"exchange": _draw_exchange(theme)
		"profile": _draw_profile(theme)

func _draw_background(theme: Dictionary) -> void:
	var base: Color = theme.base
	draw_rect(Rect2(0,CONTENT_TOP,W,CONTENT_BOTTOM-CONTENT_TOP),base,true)
	for band in range(10):
		var y: float = CONTENT_TOP + float(band)*210.0
		var light: Color = base.lightened(0.025+float(band%3)*0.012)
		draw_rect(Rect2(0,y,W,214),light,true)
	draw_rect(Rect2(0,CONTENT_TOP,75,CONTENT_BOTTOM-CONTENT_TOP),base.darkened(0.28),true)
	draw_rect(Rect2(W-75,CONTENT_TOP,75,CONTENT_BOTTOM-CONTENT_TOP),base.darkened(0.28),true)
	_draw_pattern(str(theme.pattern),theme.accent,theme.secondary)
	_draw_motes(theme.accent)

func _draw_pattern(pattern: String, accent: Color, secondary: Color) -> void:
	match pattern:
		"constellation":
			var points: Array = [Vector2(125,310),Vector2(280,250),Vector2(450,335),Vector2(650,265),Vector2(830,355),Vector2(980,280)]
			for i in range(points.size()-1): draw_line(points[i],points[i+1],Color(accent.r,accent.g,accent.b,0.12),2.0)
			for p in points: draw_circle(p,5.0,Color(accent.r,accent.g,accent.b,0.28))
		"hexgrid":
			for row in range(8):
				for col in range(6):
					var c: Vector2 = Vector2(95+col*190+(row%2)*95,270+row*235)
					_draw_hex(c,76,Color(accent.r,accent.g,accent.b,0.055))
		"chevrons":
			for row in range(9):
				var y: float = 285.0+row*220.0
				for col in range(5):
					var x: float = 85.0+col*225.0
					draw_polyline(PackedVector2Array([Vector2(x-45,y-20),Vector2(x,y+18),Vector2(x+45,y-20)]),Color(accent.r,accent.g,accent.b,0.055),5.0)
		"tracks":
			for i in range(9):
				var y2: float = 300.0+i*220.0
				draw_circle(Vector2(110+(i%2)*35,y2),16,Color(accent.r,accent.g,accent.b,0.08))
				draw_circle(Vector2(970-(i%2)*35,y2+70),12,Color(secondary.r,secondary.g,secondary.b,0.06))
		"runes":
			for i in range(6): _draw_rune(Vector2(130+(i%2)*820,340+i*320),52+float(i%3)*13,Color(accent.r,accent.g,accent.b,0.07))
		"circuits":
			for i in range(8):
				var y3: float = 300.0+i*245.0
				var x3: float = 260.0+(i%3)*110.0
				draw_line(Vector2(80,y3),Vector2(x3,y3),Color(accent.r,accent.g,accent.b,0.07),3)
				draw_line(Vector2(x3,y3),Vector2(x3,y3+70),Color(secondary.r,secondary.g,secondary.b,0.06),3)
				draw_circle(Vector2(x3,y3+70),7,Color(accent.r,accent.g,accent.b,0.12))
		"rings":
			for i in range(5): draw_arc(Vector2(540,760+i*265),100+i*18,0,TAU,48,Color(accent.r,accent.g,accent.b,0.04),3)

func _draw_motes(accent: Color) -> void:
	for i in range(18):
		var x: float = 85.0+float((i*173)%910)
		var base_y: float = 225.0+float((i*257)%1920)
		var drift: float = 0.0 if reduced_motion else sin(anim_time*(0.7+float(i%4)*0.11)+float(i))*16.0
		var alpha: float = 0.09+float(i%4)*0.025
		draw_circle(Vector2(x,base_y+drift),2.5+float(i%3),Color(accent.r,accent.g,accent.b,alpha))

func _draw_home(theme: Dictionary) -> void:
	_text("THE ASTRAL CITADEL",Vector2(76,270),22,MUTED)
	_text("Forge your crown",Vector2(76,346),60,INK)
	_text("across living arenas",Vector2(76,414),60,theme.accent)
	_draw_glass_panel(Rect2(58,485,964,875),theme.accent,0.18)
	_draw_mountains(Rect2(70,500,940,500),theme)
	var island: PackedVector2Array = PackedVector2Array([Vector2(120,1035),Vector2(220,880),Vector2(860,880),Vector2(960,1035),Vector2(850,1275),Vector2(230,1275)])
	draw_colored_polygon(island,Color("1b4936"));draw_polyline(PackedVector2Array([island[0],island[1],island[2],island[3]]),Color(theme.accent.r,theme.accent.g,theme.accent.b,0.28),4)
	draw_rect(Rect2(155,1040,770,82),Color("28748a"),true)
	for bx in [340.0,740.0]:
		draw_rect(Rect2(bx-48,1027,96,108),Color("a98350"),true)
		for p in range(4): draw_line(Vector2(bx-43,1040+p*24),Vector2(bx+43,1040+p*24),Color("60472f"),3)
	_draw_hero_tower(Vector2(540,1190),theme.accent,true,1.0);_draw_hero_tower(Vector2(310,955),Color("6d9eff"),false,0.82);_draw_hero_tower(Vector2(770,955),RED,false,0.82)
	for i in range(7):
		var px: float = 310.0+i*75.0
		var py: float = 1060.0+sin(float(i)*1.7+anim_time*1.2)*25.0
		_draw_hero_unit(Vector2(px,py),i,theme.accent if i%2==0 else ORANGE)
	_draw_rune(Vector2(540,730),105,Color(theme.accent.r,theme.accent.g,theme.accent.b,0.26))
	_text("OFFLINE TACTICAL DUELS",Vector2(115,1321),20,Color("a9ead8"))
	for i in range(3): _draw_glass_panel(Rect2(125+i*295,1390,255,90),theme.secondary,0.12)
	var labels: Array = ["24 ORIGINAL CARDS","5 LEAGUES","PERSISTENT PROGRESS"]
	for i in range(labels.size()): _text_centered(labels[i],Rect2(125+i*295,1420,255,35),16,MUTED)
	_text("VAULTS & ARCANE EXCHANGE",Vector2(145,1814),18,MUTED)

func _draw_collection(theme: Dictionary) -> void:
	_text("CARD ARCHIVE",Vector2(58,255),50,INK);_text("A living codex of units, structures and spells",Vector2(58,309),21,MUTED)
	if db==null:return
	var ids: Array = db.cards.keys();ids.sort()
	var page: int = 0 if host==null else int(host.get("collection_page"))
	var start: int = page*20;var finish: int = mini(ids.size(),start+20)
	for index in range(start,finish):
		var local: int = index-start;var col: int = local%4;var row: int = local/4
		_draw_archive_card(str(ids[index]),Rect2(45+col*250,390+row*315,230,286),theme)
	_text("ARCHIVE %d / %d"%[page+1,int(ceil(float(ids.size())/20.0))],Vector2(448,2100),18,MUTED)

func _draw_decks(theme: Dictionary) -> void:
	_text("BATTLE DECKS",Vector2(58,255),50,INK);_text("Compose an eight-card cycle and tune your Arcana curve",Vector2(58,420),21,MUTED)
	if profile==null or db==null:return
	for i in range(profile.deck.size()):
		var col: int = i%4;var row: int = i/4
		_draw_archive_card(str(profile.deck[i]),Rect2(55+col*250,510+row*430,225,350),theme,true)
	var avg: float = 0.0
	for id in profile.deck:avg+=float(db.cards[str(id)].cost)
	avg/=maxf(1.0,float(profile.deck.size()))
	_draw_glass_panel(Rect2(285,1435,510,88),theme.accent,0.18);_text_centered("AVERAGE ARCANA  %.1f"%avg,Rect2(300,1464,480,35),25,VIOLET)
	_text("OPENING CYCLE",Vector2(58,1580),20,MUTED)
	for i in range(4):_draw_archive_card(str(profile.deck[i]),Rect2(55+i*250,1620,225,330),theme,false)

func _draw_missions(theme: Dictionary) -> void:
	_text("DAILY MISSIONS",Vector2(58,255),50,INK);_text("Battle objectives etched into the expedition map",Vector2(58,310),21,MUTED)
	if profile==null:return
	for i in range(profile.missions.size()):
		var m: Dictionary = profile.missions[i];var y: float = 455.0+i*340.0
		_draw_glass_panel(Rect2(65,y,950,270),theme.accent,0.12);_draw_mission_badge(Vector2(160,y+112),i,theme)
		_text(str(m.title),Vector2(245,y+72),31,INK);_text("REWARD  %d COINS"%int(m.reward),Vector2(245,y+112),18,GOLD)
		var ratio: float = clampf(float(m.progress)/maxf(1.0,float(m.goal)),0.0,1.0)
		_draw_segmented_bar(Rect2(245,y+158,390,30),ratio,theme.accent,8);_text("%d / %d"%[int(m.progress),int(m.goal)],Vector2(245,y+222),20,MUTED)

func _draw_vaults(theme: Dictionary) -> void:
	_text("SEED VAULTS",Vector2(58,345),50,INK);_text("Arcane reliquaries that mature through battle",Vector2(58,402),21,MUTED)
	if profile==null:return
	for i in range(profile.vaults.size()):
		var v: Dictionary = profile.vaults[i];var y: float = 515.0+i*390.0;var ready: bool = bool(v.ready);var accent: Color = GOLD if ready else Color("6b7680")
		_draw_glass_panel(Rect2(92,y,896,300),accent,0.14 if ready else 0.07);_draw_vault(Vector2(245,y+155),accent,ready,1.0+float(i)*0.06)
		_text(str(v.kind),Vector2(390,y+100),35,INK);_text("%d COINS SEALED WITHIN"%int(v.coins),Vector2(390,y+150),20,GOLD);_text("READY TO OPEN" if ready else "AWAKENING",Vector2(390,y+205),19,accent)

func _draw_exchange(theme: Dictionary) -> void:
	_text("ARCANE EXCHANGE",Vector2(58,345),50,INK);_text("Infuse earned currency into your chosen cards",Vector2(58,402),21,MUTED)
	if host==null or db==null:return
	var offers: Array = host.EXCHANGE_OFFERS
	for i in range(offers.size()):
		var offer: Dictionary = offers[i];var card_id: String = str(offer.card);var y: float = 515.0+i*390.0
		_draw_glass_panel(Rect2(92,y,896,300),theme.accent,0.13);draw_circle(Vector2(222,y+232),72,Color(theme.accent.r,theme.accent.g,theme.accent.b,0.08));draw_arc(Vector2(222,y+232),62,0,TAU,30,Color(theme.secondary.r,theme.secondary.g,theme.secondary.b,0.34),4)
		_draw_archive_card(card_id,Rect2(125,y+24,190,242),theme,false);_text(str(offer.title),Vector2(370,y+89),32,INK);_text(str(db.cards[card_id].name),Vector2(370,y+132),21,MUTED);_text("INFUSION COST  %d"%int(offer.cost),Vector2(370,y+184),21,GOLD)
		for spark in range(5):
			var sy: float = y+55+spark*38+sin(anim_time*2.2+spark)*6
			draw_circle(Vector2(925-spark*12,sy),3+spark%2,Color(theme.secondary.r,theme.secondary.g,theme.secondary.b,0.24))

func _draw_profile(theme: Dictionary) -> void:
	_text("WARDEN PROFILE",Vector2(58,255),50,INK)
	if profile==null:return
	_draw_glass_panel(Rect2(60,340,960,235),theme.accent,0.16);draw_circle(Vector2(174,455),82,Color(theme.accent.r,theme.accent.g,theme.accent.b,0.10));draw_arc(Vector2(174,455),72,anim_time*0.15,anim_time*0.15+PI*1.65,40,theme.accent,5);_draw_crown_emblem(Vector2(174,455),48,theme.secondary)
	_text("CITADEL WARDEN",Vector2(285,426),33,INK);_text("ACCOUNT LEVEL %d"%profile.account_level,Vector2(285,470),20,GREEN);_text("%d CROWNS   ·   %d COINS"%[profile.trophies,profile.coins],Vector2(285,510),20,MUTED);_text("SANCTUM SETTINGS",Vector2(68,630),20,MUTED)
	var keys: Array = ["music","sfx","haptics","reduced_motion","screen_shake","high_contrast","battery_saver"];var labels: Array = ["Music","Sound effects","Haptics","Reduced motion","Screen shake","High contrast","Battery saver"]
	for i in range(keys.size()):
		var y: float = 700.0+i*190.0;_draw_glass_panel(Rect2(68,y-66,944,138),theme.accent,0.06);_draw_setting_icon(Vector2(118,y+2),i,theme.accent);_text(str(labels[i]),Vector2(164,y+7),27,INK)
		var value = profile.settings.get(str(keys[i]),false);var enabled: bool = bool(value) if typeof(value)==TYPE_BOOL else float(value)>0.0;_draw_toggle(Rect2(770,y-22,150,54),enabled,theme.accent)

func _draw_archive_card(card_id: String,rect: Rect2,theme: Dictionary,tall: bool=false)->void:
	if db==null or not db.cards.has(card_id):return
	var card: Dictionary = db.cards[card_id];var style: Dictionary = card_style(card_id,db);var accent: Color = style.accent
	draw_rect(Rect2(rect.position+Vector2(5,8),rect.size),Color(0,0,0,0.28),true);draw_rect(rect,style.frame,true);draw_rect(Rect2(rect.position+Vector2(5,5),rect.size-Vector2(10,10)),Color("182431"),true);draw_rect(Rect2(rect.position+Vector2(5,5),Vector2(rect.size.x-10,7)),accent,true)
	var art_top: Vector2 = rect.position+Vector2(14,20);var art_h: float = rect.size.y*0.52;var art_pts: PackedVector2Array = PackedVector2Array([art_top,art_top+Vector2(rect.size.x-28,0),art_top+Vector2(rect.size.x-28,art_h-18),art_top+Vector2(0,art_h)])
	draw_colored_polygon(art_pts,accent.darkened(0.56))
	for stripe in range(4):
		var sx: float = rect.position.x+26+stripe*48
		draw_line(Vector2(sx,rect.position.y+30),Vector2(sx+55,rect.position.y+art_h),Color(accent.r,accent.g,accent.b,0.055),9)
	_draw_card_glyph(rect.position+Vector2(rect.size.x*0.5,rect.size.y*0.28),str(style.family_mark),accent,card_id)
	var rarity: String = str(style.rarity_mark);var jewel_count: int = 1
	if rarity=="rare":jewel_count=2
	elif rarity=="epic":jewel_count=3
	elif rarity=="legendary":jewel_count=4
	for j in range(jewel_count):draw_circle(rect.position+Vector2(rect.size.x-18-j*13,18),4,accent.lightened(0.28))
	_text_centered(str(card.name),Rect2(rect.position.x+8,rect.position.y+rect.size.y*0.58,rect.size.x-16,34),16 if rect.size.x<220 else 17,INK);draw_circle(rect.position+Vector2(29,30),22,VIOLET);_text_centered(str(card.cost),Rect2(rect.position.x+10,rect.position.y+15,38,23),16,Color.WHITE)
	var level: int = 1 if profile==null else int(profile.levels.get(card_id,1));_text("LV.%d"%level,rect.position+Vector2(14,rect.size.y-17),13,MUTED)
	if rect.size.y>300:_text(str(card.family).to_upper(),rect.position+Vector2(14,rect.size.y-46),12,accent)

func _draw_card_glyph(center: Vector2,family_mark: String,accent: Color,card_id: String)->void:
	if family_mark=="tower":
		draw_rect(Rect2(center-Vector2(34,4),Vector2(68,42)),accent.darkened(0.3),true);draw_rect(Rect2(center-Vector2(26,36),Vector2(52,42)),accent,true)
		for x in [-18.0,0.0,18.0]:draw_rect(Rect2(center+Vector2(x-6,-46),Vector2(12,15)),accent.lightened(0.18),true)
	elif family_mark=="rune":_draw_rune(center,36,accent)
	else:
		var variant: int = int(abs(card_id.hash())%5)
		draw_circle(center+Vector2(0,-9),27,accent)
		if variant==0:draw_colored_polygon(PackedVector2Array([center+Vector2(-22,-28),center+Vector2(0,-55),center+Vector2(22,-28)]),accent.lightened(0.2))
		elif variant==1:draw_arc(center+Vector2(0,-10),38,PI,TAU,16,accent.lightened(0.22),7)
		elif variant==2:draw_line(center+Vector2(-38,-4),center+Vector2(38,-4),accent.lightened(0.22),10)
		elif variant==3:draw_colored_polygon(PackedVector2Array([center+Vector2(-22,-25),center+Vector2(-12,-52),center+Vector2(0,-28),center+Vector2(14,-54),center+Vector2(23,-24)]),accent.lightened(0.2))
		else:
			for a in [-1.0,1.0]:draw_line(center+Vector2(a*13,-27),center+Vector2(a*31,-48),accent.lightened(0.2),7)
		draw_circle(center+Vector2(-8,-10),3.5,Color.WHITE);draw_circle(center+Vector2(8,-10),3.5,Color.WHITE);draw_colored_polygon(PackedVector2Array([center+Vector2(-28,16),center+Vector2(28,16),center+Vector2(20,48),center+Vector2(-20,48)]),accent.darkened(0.32))

func _draw_glass_panel(rect: Rect2,accent: Color,glow: float)->void:
	draw_rect(Rect2(rect.position+Vector2(5,8),rect.size),Color(0,0,0,0.28),true);draw_rect(rect,Color("172536"),true);draw_rect(Rect2(rect.position+Vector2(2,2),Vector2(rect.size.x-4,2)),Color(1,1,1,0.07),true);draw_rect(Rect2(rect.position,Vector2(5,rect.size.y)),Color(accent.r,accent.g,accent.b,0.55+glow),true)
	if glow>0.1:draw_rect(Rect2(rect.position+Vector2(6,6),rect.size-Vector2(12,12)),Color(accent.r,accent.g,accent.b,glow*0.05),true)

func _draw_hex(center: Vector2,r: float,color: Color)->void:
	var pts: PackedVector2Array = PackedVector2Array()
	for i in range(6):
		var a: float = TAU*float(i)/6.0;pts.append(center+Vector2(cos(a),sin(a))*r)
	pts.append(pts[0]);draw_polyline(pts,color,2)

func _draw_rune(center: Vector2,radius: float,color: Color)->void:
	var pulse: float = 1.0 if reduced_motion else 1.0+sin(anim_time*2.2+center.y*0.01)*0.035;var r: float = radius*pulse
	draw_arc(center,r,0,TAU,30,color,3);draw_arc(center,r*0.63,anim_time*0.15,anim_time*0.15+PI*1.45,22,Color(color.r,color.g,color.b,color.a*0.8),2)
	for i in range(4):
		var a: float = TAU*float(i)/4.0+anim_time*0.07
		draw_line(center+Vector2(cos(a),sin(a))*r*0.25,center+Vector2(cos(a),sin(a))*r*0.78,color,2)

func _draw_mountains(rect: Rect2,theme: Dictionary)->void:
	var far: PackedVector2Array = PackedVector2Array([Vector2(rect.position.x,rect.position.y+rect.size.y),Vector2(rect.position.x+110,rect.position.y+255),Vector2(rect.position.x+235,rect.position.y+390),Vector2(rect.position.x+360,rect.position.y+180),Vector2(rect.position.x+520,rect.position.y+365),Vector2(rect.position.x+690,rect.position.y+205),Vector2(rect.end.x,rect.position.y+rect.size.y)]);draw_colored_polygon(far,Color("132c35"))
	var near: PackedVector2Array = PackedVector2Array([Vector2(rect.position.x,rect.end.y),Vector2(rect.position.x+155,rect.position.y+350),Vector2(rect.position.x+300,rect.end.y),Vector2(rect.position.x+510,rect.position.y+315),Vector2(rect.position.x+740,rect.end.y),Vector2(rect.end.x,rect.position.y+330),Vector2(rect.end.x,rect.end.y)]);draw_colored_polygon(near,Color("183b36"))
	for i in range(8):
		var x: float = rect.position.x+80+i*120;var y: float = rect.position.y+95+sin(i*1.7)*35
		draw_circle(Vector2(x,y),3+float(i%3),Color(theme.accent.r,theme.accent.g,theme.accent.b,0.22))

func _draw_hero_tower(pos: Vector2,accent: Color,core: bool,scale_factor: float)->void:
	var w: float = (112.0 if core else 88.0)*scale_factor;var h: float = (145.0 if core else 112.0)*scale_factor
	draw_circle(pos+Vector2(0,h*0.38),w*0.68,Color(0,0,0,0.25));var pts: PackedVector2Array = PackedVector2Array([pos+Vector2(-w*.52,h*.37),pos+Vector2(w*.52,h*.37),pos+Vector2(w*.39,-h*.36),pos+Vector2(-w*.39,-h*.36)]);draw_colored_polygon(pts,accent.darkened(0.45));draw_rect(Rect2(pos+Vector2(-w*.48,-h*.5),Vector2(w*.96,h*.22)),accent.darkened(0.08),true)
	for dx in [-.32,0.0,.32]:draw_rect(Rect2(pos+Vector2(w*dx-9,-h*.64),Vector2(18,h*.2)),accent.lightened(.13),true)
	if core:_draw_crown_emblem(pos+Vector2(0,-4),22*scale_factor,GOLD)

func _draw_hero_unit(pos: Vector2,index: int,accent: Color)->void:
	var bob: float = 0.0 if reduced_motion else sin(anim_time*3.0+index)*4;var p: Vector2 = pos+Vector2(0,bob)
	draw_circle(p+Vector2(0,21),25,Color(0,0,0,.28));draw_circle(p+Vector2(0,-14),18,accent);draw_rect(Rect2(p+Vector2(-17,2),Vector2(34,39)),accent.darkened(.32),true)
	if index%3==0:draw_line(p+Vector2(18,7),p+Vector2(38,-26),GOLD,5)
	elif index%3==1:draw_circle(p+Vector2(-25,9),11,accent.lightened(.22))
	else:draw_colored_polygon(PackedVector2Array([p+Vector2(-15,-28),p+Vector2(0,-45),p+Vector2(15,-28)]),accent.lightened(.18))

func _draw_mission_badge(center: Vector2,index: int,theme: Dictionary)->void:
	draw_circle(center,61,Color(theme.accent.r,theme.accent.g,theme.accent.b,.10));draw_arc(center,52,0,TAU,24,theme.accent,4)
	if index%3==0:
		for a in range(4):draw_line(center,center+Vector2(cos(TAU*a/4.0),sin(TAU*a/4.0))*30,theme.secondary,5)
	elif index%3==1:_draw_crown_emblem(center,29,theme.secondary)
	else:_draw_rune(center,30,theme.secondary)

func _draw_segmented_bar(rect: Rect2,ratio: float,accent: Color,segments: int)->void:
	var gap: float = 5.0;var sw: float = (rect.size.x-gap*(segments-1))/segments
	for i in range(segments):
		var fill: bool = ratio*segments>i;draw_rect(Rect2(rect.position+Vector2(i*(sw+gap),0),Vector2(sw,rect.size.y)),accent if fill else Color("273544"),true)

func _draw_vault(center: Vector2,accent: Color,ready: bool,scale_factor: float)->void:
	var pulse: float = 1.0 if reduced_motion else 1.0+sin(anim_time*2.4+center.y*.01)*(.025 if ready else .008);var s: float = scale_factor*pulse
	draw_circle(center+Vector2(0,38)*s,78*s,Color(0,0,0,.25));draw_rect(Rect2(center-Vector2(74,40)*s,Vector2(148,110)*s),accent.darkened(.48),true);draw_rect(Rect2(center-Vector2(68,63)*s,Vector2(136,42)*s),accent.darkened(.08),true);draw_rect(Rect2(center+Vector2(-9,-8)*s,Vector2(18,48)*s),accent.lightened(.27),true)
	if ready:draw_circle(center+Vector2(0,7)*s,21*s,Color(accent.r,accent.g,accent.b,.25));_draw_rune(center+Vector2(0,7)*s,14*s,accent.lightened(.25))

func _draw_setting_icon(center: Vector2,index: int,accent: Color)->void:
	draw_circle(center,25,Color(accent.r,accent.g,accent.b,.11));draw_arc(center,18,0,TAU,20,accent,3)
	if index%2==0:draw_line(center-Vector2(10,0),center+Vector2(10,0),accent.lightened(.2),4)
	else:draw_line(center-Vector2(0,10),center+Vector2(0,10),accent.lightened(.2),4)

func _draw_toggle(rect: Rect2,enabled: bool,accent: Color)->void:
	var bg: Color = accent.darkened(.38) if enabled else Color("344553");draw_rect(rect,bg,true);var knob_x: float = rect.end.x-28 if enabled else rect.position.x+28;draw_circle(Vector2(knob_x,rect.position.y+rect.size.y*.5),20,accent.lightened(.2) if enabled else MUTED)

func _draw_crown_emblem(center: Vector2,r: float,color: Color)->void:
	var pts: PackedVector2Array = PackedVector2Array([center+Vector2(-r*.7,r*.28),center+Vector2(-r*.55,-r*.55),center+Vector2(-r*.15,-r*.08),center+Vector2(0,-r*.78),center+Vector2(r*.18,-r*.08),center+Vector2(r*.58,-r*.56),center+Vector2(r*.72,r*.28)]);draw_colored_polygon(pts,color.darkened(.15));draw_rect(Rect2(center+Vector2(-r*.7,r*.20),Vector2(r*1.42,r*.28)),color,true)

func _card_accent(card_id: String)->Color:
	var fixed: Dictionary = {"iron_warden":Color("6ec6ff"),"moss_colossus":Color("78b85c"),"astral_sentinel":Color("a59bff"),"spore_bomber":Color("d99a69"),"gearling_trio":Color("f0b85b"),"dune_lancer":Color("e7c17a"),"ember_fox":Color("ff754d"),"tempest_oracle":Color("65d9e8"),"crystal_witch":Color("c477ff"),"lumen_swarm":Color("fff08a"),"storm_knight":Color("7ca8ff"),"root_mender":Color("6fc77b"),"void_manta":Color("8d6bd8"),"sunforged_ram":Color("ffc85a"),"rune_duelist":Color("e66c9c"),"frost_owl":Color("b8efff"),"thorn_bastion":Color("6a9b58"),"prism_turret":Color("a779ff"),"arc_coil":Color("6bd6ff"),"sunwell":Color("ffcf5c"),"starfall":Color("9f86ff"),"gale_ring":Color("7ee1cf"),"bloom_pulse":Color("80e68e"),"time_shard":Color("79aaff")}
	if fixed.has(card_id):return fixed[card_id]
	return Color.from_hsv(float(abs(card_id.hash())%1000)/1000.0,.58,.92)

func _text(text: String,pos: Vector2,size_px: int,color: Color)->void:
	draw_string(ThemeDB.fallback_font,pos,text,HORIZONTAL_ALIGNMENT_LEFT,-1,size_px,color)
func _text_centered(text: String,rect: Rect2,size_px: int,color: Color)->void:
	draw_string(ThemeDB.fallback_font,rect.position+Vector2(0,size_px),text,HORIZONTAL_ALIGNMENT_CENTER,rect.size.x,size_px,color)
