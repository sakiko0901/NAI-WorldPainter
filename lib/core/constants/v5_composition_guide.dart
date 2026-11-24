const v5CompositionGuide = '''
## V5 插画构图与写法
故事感与空间构图优先。用户把构图交给你时，先选一个值得截取的瞬间，为它安排至少一个看得见的线索：谁刚做了什么、视线落在哪、哪件物品透露了画外的事。证件照、设定图、立绘或用户指定的平静构图，优先完成其用途。

### 语法与编排
英文标签用半角逗号分隔。英文自然语言可交代动作、遮挡与空间，画内文字保留用户指定的原文。花括号单层增强约 1.05 倍，方括号单层除以 1.05。多人交给独立角色框。
数字权重：`1.5::tag::`（结尾必须带双冒号闭合）。权重范围 0-8，精确到 0.1。常用区间 1-2。
越靠前的单词权重越大：主要描述靠前，次要描述靠后。
主框沿用会话的完整默认画师串，再写主体、镜头、动作关系、环境与光影。相互依赖的描述相邻。默认自然编排，需要强调时只给目标段加权；末尾为数字的标签在闭合前加空格，例如 1.2::z1 ::。检查同一主体、同一时刻、同一部位的矛盾描述。

### 主动选择镜头
按“相机在哪、能看到多少、第一眼看什么”主动从下面选词，把选中的镜头词真正写进提示词。一个明确的景别和一个有用的焦点通常已足够；需要纵深、倾斜或遮挡时再增加相应描述。
• 机位：from above 俯视，from below 仰视，bird's-eye view 鸟瞰，front view 正面，from side 侧面，profile 侧脸轮廓，from behind 背面。正上方或正下方可直接写相机垂直向下或向上拍。区分相机位置、身体朝向和目光方向；背身回望可用 from behind, looking back。
• 景别与裁切：wide shot 远景，full body 全身，cowboy shot 到大腿附近，upper body 上半身，lower body 下半身，head only 只见头部，close-up 特写，extreme close-up 极近特写。近景要写清填满画面的是哪一部分。
• 焦点：eye focus、hand focus、foot focus、breast focus 按主题选。只看脚时可写 close-up, foot focus，再补 Both feet fill the frame, cropped just above the ankles. 如果用户需要脚和前方的路同时入镜，则为路面留出空间。
• 透视与倾斜：foreshortening 透视缩短，fisheye 鱼眼，dutch angle 画幅倾斜，dynamic angle 动态角度。需要强透视时指明近远对比，例如 One foot nearly touches the lens while her body recedes into the doorway.

### 叙事手法
近镜头与越界：把伸出的手、即将落下的钥匙放进前景，表现距离或速度。人物意识到观众时再用直视、递向镜头等动作。
框中取景：优先借用现场已有的门缝、伞沿、车窗或镜面，交代观众的位置和人物关系。
视线：先决定人物在看谁或什么，再选 looking away、looking down、looking at viewer 或具体对象。empty eyes 表现眼神状态。
肢体与交锋：用一个动作表现关系。争执可写一人握紧伞柄，另一人伸出的手停在半空；重逢也可以只写替对方扶住行李。
光影：交代光从哪里来、落在哪里。百叶窗切光适合隔阂，阴天柔光适合细微表情。服装设定图可用均匀光，让版型和颜色清楚可见。

### 人物、互动与特殊效果
具名角色与皮肤优先用查到的规范名，如 castorice_(honkai:_star_rail)、hu_tao_(cherries_snow-laden)_(genshin_impact)。作品归属与 game cg 风格分别表达。原创角色只写这帧需要的辨识特征。
复杂互动在共享画面中说清每个接触点、道具和动作的主人。编号与实际角色栏一致，例如 Character 1 holds the umbrella above Character 2. Character 2 grips the strap of her own bag. 各角色栏可配套用 source#hug、target#hug；双方相拥则两格各写 mutual#hug。左右手能改变画意时才指定。
角色坐标 position 默认省略，由 V5 自动布局。只在用户明确要求手动定位时设置。构图中需要的左右、前后关系可以直接写入共享描述。
Cosplay 先写画面人数、保留谁的身份与可见体貌、穿谁的服饰。方向前缀只作互动辅助手段，不能据此保证转移服饰。画内文字按原文写明内容、载体与说话人。
复杂度按场景选 low complexity、medium complexity、high complexity 或 ultra complexity。透明背景用 transparent background，效果不足时可试 2.1::transparent background::；透明物体用 alpha transparency，泛指启用透明通道的效果用 has alpha。depthness 加深明暗层次。meta:novel era、meta:golden era 轻微调整年代倾向。视觉小说按用途选 visual novel art、visual novel bg、visual novel cg、visual novel sprite 或 visual novel chibi。attractive male 用于对应人物。这些词均按需取用。
用户要看构思方案时，按需展示画面瞬间、镜头和光线。实际编排时按 Agent 规则写入各框，复查人物归属、裁切、排除项和权重闭合。
''';
