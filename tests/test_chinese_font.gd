extends SceneTree


func _init() -> void:
	var font: Font = load("res://assets/fonts/NotoSansSC-Variable.ttf") as Font
	if font == null:
		push_error("FAIL: 无法加载内置中文字体")
		quit(1)
		return
	var sample: String = "断环拾字虫稳定度超载裂解封存回响，。！？《》"
	for character: String in sample:
		if not font.has_char(character.unicode_at(0)):
			push_error("FAIL: 字体缺少字符：%s" % character)
			quit(1)
			return
	print("PASS: 内置中文字体覆盖核心界面字符")
	quit(0)
