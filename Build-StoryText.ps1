param(
    [string]$SourceDirectory = $PSScriptRoot,
    [string]$OutputDirectory = [Environment]::GetFolderPath([Environment+SpecialFolder]::DesktopDirectory)
)

try {
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$speakerNames = @{
    player = '沈砚'
    sw     = '苏晚'
    zly    = '钟凌羽'
    zhao   = '老赵'
    teng   = '藤原'
    Li     = '老李'
    ls     = '老师'
}

function Convert-RenPyText {
    param([string]$Text)

    $value = $Text
    $value = $value -replace '\\n', "`r`n"
    $value = $value -replace '\\r', "`r"
    $value = $value -replace '\\t', "`t"
    $value = $value -replace '\\"', '"'
    $value = $value -replace '\\\\', '\'
    $value = $value -replace '\{tipid=[^}]+\}', ''
    $value = $value -replace '\{/tipid\}', ''
    $value = $value -replace '\{w(?:=[^}]*)?\}', ''
    $value = $value -replace '\{nw\}', ''
    $value = $value.Replace('[[', '[')
    $value = $value.Replace('%%', '%')
    return $value
}

function New-StoryEntry {
    param(
        [string]$Chapter,
        [string]$SourceFile,
        [int]$StartLine,
        [int]$EndLine,
        [AllowNull()][string]$Speaker,
        [string]$Text
    )

    [PSCustomObject]@{
        Chapter    = $Chapter
        SourceFile = $SourceFile
        StartLine  = $StartLine
        EndLine    = $EndLine
        Speaker    = $Speaker
        Text       = $Text
    }
}

function Test-StorySyntaxCoverage {
    param([Parameter(Mandatory)][string]$Path)

    $sourceFile = [IO.Path]::GetFileName($Path)
    $lines = [IO.File]::ReadAllLines($Path, [Text.Encoding]::UTF8)
    $inTriple = $false

    for ($index = 0; $index -lt $lines.Length; $index++) {
        $lineNumber = $index + 1
        $trimmed = $lines[$index].Trim()

        if ($trimmed -eq '"""') {
            $inTriple = -not $inTriple
            continue
        }

        if ($inTriple) {
            if ($trimmed -match '(?<!\[)\[(?!\[)[A-Za-z_][^\]]*\]' -or $trimmed -match '%\([A-Za-z_][^)]*\)[#0 +\-]?\d*(?:\.\d+)?[A-Za-z]') {
                throw "Unsupported text interpolation in ${sourceFile}:$lineNumber. Resolve the displayed value before extracting."
            }
            $unknownTagText = $trimmed -replace '\{tipid=[^}]+\}|\{/tipid\}|\{w(?:=[^}]*)?\}|\{nw\}', ''
            if ($unknownTagText -match '\{[^}\r\n]+\}') {
                throw "Unsupported Ren'Py text tag in ${sourceFile}:${lineNumber}: $($Matches[0])"
            }
            continue
        }

        if ($trimmed.Length -eq 0 -or $trimmed.StartsWith('#') -or $trimmed -notmatch '"') {
            continue
        }

        $isVisibleText =
            $trimmed -match '^\$\s*phone_me\("(?<text>(?:\\.|[^"\\])*)"(?:\s*,\s*time\s*=\s*"(?<time>[^"]*)")?\s*\)\s*$' -or
            $trimmed -match '^\$\s*phone_other\("(?<text>(?:\\.|[^"\\])*)"\s*,\s*who\s*=\s*(?<who>[A-Za-z_][A-Za-z0-9_]*)(?:\s*,\s*time\s*=\s*"(?<time>[^"]*)")?\s*\)\s*$' -or
            $trimmed -match '^\$\s*renpy\.notify\("(?<text>(?:\\.|[^"\\])*)"\)\s*$' -or
            $trimmed -match '^(?:centered|narrator|text)\s+"(?<text>(?:\\.|[^"\\])*)"\s*$' -or
            $trimmed -match '^show\s+text\s+"(?<text>(?:\\.|[^"\\])*)"(?:\s+.+)?$' -or
            $trimmed -match '^extend\s+"(?<text>(?:\\.|[^"\\])*)"\s*$' -or
            $trimmed -match '^"(?<speaker>(?:\\.|[^"\\])*)"\s+"(?<text>(?:\\.|[^"\\])*)"\s*$' -or
            $trimmed -match '^(?<speaker>[A-Za-z_][A-Za-z0-9_\.]*)\s+"(?<text>(?:\\.|[^"\\])*)"\s*$' -or
            $trimmed -match '^"(?<text>(?:\\.|[^"\\])*)"\s*$'

        if ($isVisibleText) {
            if ($trimmed -match '(?<!\[)\[(?!\[)[A-Za-z_][^\]]*\]' -or $trimmed -match '%\([A-Za-z_][^)]*\)[#0 +\-]?\d*(?:\.\d+)?[A-Za-z]') {
                throw "Unsupported text interpolation in ${sourceFile}:$lineNumber. Resolve the displayed value before extracting."
            }
            $unknownTagText = $trimmed -replace '\{tipid=[^}]+\}|\{/tipid\}|\{w(?:=[^}]*)?\}|\{nw\}', ''
            if ($unknownTagText -match '\{[^}\r\n]+\}') {
                throw "Unsupported Ren'Py text tag in ${sourceFile}:${lineNumber}: $($Matches[0])"
            }
            continue
        }

        $isKnownNonStoryString =
            $trimmed -match '^\$\s*achievement\.grant\("(?:\\.|[^"\\])*"\)\s*$' -or
            $trimmed -match '^(?:play|queue)\s+(?:music|sound|audio)\b' -or
            $trimmed -match '^(?:show|hide|scene)\b'

        if (-not $isKnownNonStoryString) {
            throw "Unrecognized string-bearing Ren'Py syntax in ${sourceFile}:${lineNumber}: $trimmed"
        }
    }

    if ($inTriple) {
        throw "Unclosed triple-quoted text in $sourceFile."
    }
}

function Get-StoryEntries {
    param(
        [Parameter(Mandatory)][string]$Path,
        [int]$FromLine = 1,
        [int]$ToLine = [int]::MaxValue
    )

    $chapter = [IO.Path]::GetFileNameWithoutExtension($Path)
    $sourceFile = [IO.Path]::GetFileName($Path)
    $lines = [IO.File]::ReadAllLines($Path, [Text.Encoding]::UTF8)
    $entries = [Collections.Generic.List[object]]::new()
    $inTriple = $false

    for ($index = 0; $index -lt $lines.Length; $index++) {
        $lineNumber = $index + 1
        $trimmed = $lines[$index].Trim()

        if ($trimmed -eq '"""') {
            $inTriple = -not $inTriple
            continue
        }

        if ($inTriple) {
            if ($lineNumber -ge $FromLine -and $lineNumber -le $ToLine -and $trimmed.Length -gt 0) {
                $entries.Add((New-StoryEntry $chapter $sourceFile $lineNumber $lineNumber $null (Convert-RenPyText $trimmed)))
            }
            continue
        }

        if ($lineNumber -lt $FromLine -or $lineNumber -gt $ToLine) {
            continue
        }

        if ($trimmed.Length -eq 0 -or $trimmed.StartsWith('#')) {
            continue
        }

        if ($trimmed -match '^\$\s*renpy\.notify\("(?<text>(?:\\.|[^"\\])*)"\)\s*$') {
            $entries.Add((New-StoryEntry $chapter $sourceFile $lineNumber $lineNumber $null (Convert-RenPyText $Matches.text)))
            continue
        }

        if ($trimmed -match '^(?:centered|narrator|text)\s+"(?<text>(?:\\.|[^"\\])*)"\s*$') {
            $entries.Add((New-StoryEntry $chapter $sourceFile $lineNumber $lineNumber $null (Convert-RenPyText $Matches.text)))
            continue
        }

        if ($trimmed -match '^show\s+text\s+"(?<text>(?:\\.|[^"\\])*)"(?:\s+.+)?$') {
            $entries.Add((New-StoryEntry $chapter $sourceFile $lineNumber $lineNumber $null (Convert-RenPyText $Matches.text)))
            continue
        }

        if ($trimmed -match '^\$\s*phone_me\("(?<text>(?:\\.|[^"\\])*)"(?:\s*,\s*time\s*=\s*"(?<time>[^"]*)")?\s*\)\s*$') {
            $phoneText = Convert-RenPyText $Matches.text
            if ($Matches.time) { $phoneText = "〔$($Matches.time)〕$phoneText" }
            $entries.Add((New-StoryEntry $chapter $sourceFile $lineNumber $lineNumber '沈砚' $phoneText))
            continue
        }

        if ($trimmed -match '^\$\s*phone_other\("(?<text>(?:\\.|[^"\\])*)"\s*,\s*who\s*=\s*(?<who>[A-Za-z_][A-Za-z0-9_]*)(?:\s*,\s*time\s*=\s*"(?<time>[^"]*)")?\s*\)\s*$') {
            $phoneText = Convert-RenPyText $Matches.text
            $who = $Matches.who
            $speaker = if ($speakerNames.ContainsKey($who)) { $speakerNames[$who] } else { $who }
            if ($Matches.time) { $phoneText = "〔$($Matches.time)〕$phoneText" }
            $entries.Add((New-StoryEntry $chapter $sourceFile $lineNumber $lineNumber $speaker $phoneText))
            continue
        }

        if ($trimmed -match '^extend\s+"(?<text>(?:\\.|[^"\\])*)"\s*$') {
            if ($entries.Count -eq 0) {
                throw "extend at ${sourceFile}:$lineNumber has no preceding visible text in the selected range."
            }
            $last = $entries[$entries.Count - 1]
            $last.Text += Convert-RenPyText $Matches.text
            $last.EndLine = $lineNumber
            continue
        }

        if ($trimmed -match '^"(?<speaker>(?:\\.|[^"\\])*)"\s+"(?<text>(?:\\.|[^"\\])*)"\s*$') {
            $entries.Add((New-StoryEntry $chapter $sourceFile $lineNumber $lineNumber (Convert-RenPyText $Matches.speaker) (Convert-RenPyText $Matches.text)))
            continue
        }

        if ($trimmed -match '^(?<speaker>[A-Za-z_][A-Za-z0-9_\.]*)\s+"(?<text>(?:\\.|[^"\\])*)"\s*$') {
            $who = $Matches.speaker
            $speaker = if ($speakerNames.ContainsKey($who)) { $speakerNames[$who] } else { $who }
            $entries.Add((New-StoryEntry $chapter $sourceFile $lineNumber $lineNumber $speaker (Convert-RenPyText $Matches.text)))
            continue
        }

        if ($trimmed -match '^"(?<text>(?:\\.|[^"\\])*)"\s*$') {
            $entries.Add((New-StoryEntry $chapter $sourceFile $lineNumber $lineNumber $null (Convert-RenPyText $Matches.text)))
            continue
        }
    }

    if ($inTriple) {
        throw "Unclosed triple-quoted text in $sourceFile."
    }

    return $entries
}

function Format-StoryEntry {
    param([Parameter(Mandatory)]$Entry)

    if ($null -ne $Entry.Speaker -and $Entry.Speaker.Length -gt 0) {
        return '{0}：{1}' -f $Entry.Speaker, $Entry.Text
    }
    return $Entry.Text
}

$chapterFiles = 0..9 | ForEach-Object {
    $path = Join-Path $SourceDirectory ("chapter_{0}.rpy" -f $_)
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Missing required chapter file: $path"
    }
    $path
}

foreach ($path in $chapterFiles) {
    Test-StorySyntaxCoverage -Path $path
}

$allEntriesByChapter = @{}
$completeParts = [Collections.Generic.List[string]]::new()
$completeParts.Add('《夏梦》完整剧情原文')
$completeParts.Add('')

for ($chapterNumber = 0; $chapterNumber -le 9; $chapterNumber++) {
    $path = $chapterFiles[$chapterNumber]
    $entries = @(Get-StoryEntries -Path $path)
    if ($entries.Count -eq 0) {
        throw "No visible story text extracted from chapter_$chapterNumber.rpy."
    }
    $allEntriesByChapter[$chapterNumber] = $entries
    $completeParts.Add(('==================== 第{0}章 ====================' -f $chapterNumber))
    $completeParts.Add('')
    foreach ($entry in $entries) {
        $completeParts.Add((Format-StoryEntry $entry))
        $completeParts.Add('')
    }
}

while ($completeParts.Count -gt 0 -and $completeParts[$completeParts.Count - 1] -eq '') {
    $completeParts.RemoveAt($completeParts.Count - 1)
}

$sceneDefinitions = @(
    @{ File='chapter_0.rpy'; Start=7; End=9; Title='架空战争与东瀛背景'; Note='交代倭国核攻击失败、主角迁居东瀛的世界观背景。' },
    @{ File='chapter_0.rpy'; Start=319; End=378; Title='性别议题：偷拍诬告事件'; Note='围绕偷拍指控、监控证据、校方态度和公开道歉展开。' },
    @{ File='chapter_0.rpy'; Start=443; End=543; Title='民族与校园：苏晚帮助被霸凌的东瀛女生'; Note='表现漢人、东瀛人分班及苏晚对民族身份的看法。' },
    @{ File='chapter_0.rpy'; Start=550; End=579; Title='男性网络亚文化：二游、麻辣与“龟龟”话题'; Note='主角浏览男性向游戏社区时出现的网络黑话和群体评价。' },
    @{ File='chapter_0.rpy'; Start=834; End=1004; Title='治安与民族主义：混混、旭日徽章和东瀛治安'; Note='完整保留沈砚介入骚扰、钟凌羽执法及旭日组织线索。' },
    @{ File='chapter_1.rpy'; Start=81; End=141; Title='性别议题：对女生话题与择偶审查的评价'; Note='苏晚谈及原生家庭、社会压迫，并要求替沈砚审核女友。' },
    @{ File='chapter_2.rpy'; Start=197; End=323; Title='兄妹关系：卧室中的性意识'; Note='苏晚仍以妹妹身份进入沈砚卧室，两人第一次明确意识到身体和性别差异。' },
    @{ File='chapter_2.rpy'; Start=648; End=882; Title='性别双重标准：考试插排事件'; Note='以男女分考场的插排共享差异讨论资源、举报压力和“男生该大度”。' },
    @{ File='chapter_3.rpy'; Start=79; End=109; Title='民族同化：东瀛身份与倭国消亡'; Note='正面角色讨论东瀛人认同华夏以及下一代身份同化。' },
    @{ File='chapter_3.rpy'; Start=978; End=1150; Title='民族与校园：藤原、霸凌和报复威胁'; Note='藤原感谢苏晚并说明东瀛不良少女准备报复的前因后果。' },
    @{ File='chapter_3.rpy'; Start=1241; End=1308; Title='恋爱与诬告焦虑：苏晚吃醋及“帽子”担忧'; Note='苏晚得知钟凌羽入队后的反应，以及沈砚对恋爱风险的表达。' },
    @{ File='chapter_4.rpy'; Start=10; End=37; Title='政治与历史：高考作文和伟大复兴'; Note='三名主角围绕民族历史、文化根脉和伟大复兴讨论作文立意。' },
    @{ File='chapter_4.rpy'; Start=374; End=633; Title='民族主义：天台对峙与“华夏正统”'; Note='完整保留苏晚、沈砚与佐藤从校园霸凌升级到民族和制度争论的场景。' },
    @{ File='chapter_4.rpy'; Start=684; End=865; Title='性别与执法：占用消防通道及诬称打人'; Note='保留女司机违法、推搡、诬告和钟凌羽事后疲惫的完整过程。' },
    @{ File='chapter_4.rpy'; Start=888; End=942; Title='文化复兴：华夏、衣冠与礼仪'; Note='三人从漢服谈到“华”与“夏”的含义及义务教育中的文化传承。' },
    @{ File='chapter_5.rpy'; Start=685; End=766; Title='历史与民族：漢字、漢服及“心中的辫子”'; Note='苏晚和沈砚讨论漢民族名称、剃发易服和漢服复兴。' },
    @{ File='chapter_5.rpy'; Start=768; End=829; Title='媒体审查与历史：错误电影引发的讨论'; Note='三人围绕历史题材电影、过审、先烈和文化解构表达观点。' },
    @{ File='chapter_6.rpy'; Start=15; End=60; Title='性别议题：“男人节”与好漢节'; Note='把8月3日设为男性节日，并与妇女节、英雌等网络概念对照。' },
    @{ File='chapter_6.rpy'; Start=112; End=158; Title='男性网络亚文化：后宫文、百合、CP与性别不明主角'; Note='三人讨论后宫文争议、抽卡游戏社群和非男性中心内容。' },
    @{ File='chapter_6.rpy'; Start=264; End=388; Title='媒体与执法：断章取义的“暴力执法”新闻'; Note='保留新闻片段、停职原因、被制止女性踩踏老人及人物回应。' },
    @{ File='chapter_6.rpy'; Start=608; End=701; Title='舆论与社会：媒体职能和美德消失'; Note='钟凌羽说明停职后的失望，沈砚将其解释为舆论阵地和社会撕裂。' },
    @{ File='chapter_6.rpy'; Start=758; End=852; Title='政治表达：文化复兴、禁言与“没有硝烟的战争”'; Note='三人在火锅店讨论物质建设、华夏精神、发声、禁言和革命传统。' },
    @{ File='chapter_7.rpy'; Start=920; End=1003; Title='现实观点：恢复职务与网络政治群体'; Note='从钟凌羽恢复职务延伸到网上发声、大旗党、道德绑架和网络对线。' },
    @{ File='chapter_7.rpy'; Start=1159; End=1231; Title='恋爱观：青梅与天降坦白竞争'; Note='苏晚和钟凌羽互相承认喜欢沈砚，并讨论男性、纸片人和真爱。' },
    @{ File='chapter_8.rpy'; Start=32; End=118; Title='民族与恋爱：东瀛女生寻找漢人男友'; Note='藤原与苏晚讨论漢人男性、东瀛版本差异和沈砚的归属。' },
    @{ File='chapter_8.rpy'; Start=151; End=208; Title='兄妹与纸片人：沈砚的理想女性'; Note='钟凌羽询问沈砚喜欢的类型，话题直接涉及苏晚和妹系角色。' },
    @{ File='chapter_8.rpy'; Start=243; End=364; Title='兄妹关系：高三苏晚的约会打扮与身体接触'; Note='苏晚以邻家妹妹身份约沈砚出门，双方出现明确的性吸引描写。' },
    @{ File='chapter_8.rpy'; Start=408; End=437; Title='游戏与政治正确：女性替换主角及DEI'; Note='沈砚和苏晚因游戏更换男性主角而讨论政治正确和DEI。' },
    @{ File='chapter_8.rpy'; Start=492; End=600; Title='兄妹恋爱：苏晚向沈砚确认感情'; Note='保留苏晚担心被抢走、要求考入朝大以及两人互相承认喜欢的完整场景。' },
    @{ File='chapter_8.rpy'; Start=907; End=985; Title='恋爱观：钟凌羽表白并要求给“两人”答案'; Note='钟凌羽在摩天轮表白，并明确沈砚需要同时面对她和苏晚。' },
    @{ File='chapter_9.rpy'; Start=15; End=53; Title='婚恋伦理：父母要求一心一意'; Note='沈砚父母强调不能欺骗、拖延，应当一心一意对待恋人。' },
    @{ File='chapter_9.rpy'; Start=81; End=138; Title='婚姻与后宫：婚姻坟墓及“大家一起幸福”'; Note='沈砚与老赵从婚姻负面视频谈到动画后宫结局。' },
    @{ File='chapter_9.rpy'; Start=188; End=283; Title='后宫与纯爱：两位女主协商及沈砚的结论'; Note='苏晚和钟凌羽先达成不退出的共识，沈砚随后定义“后宫纯爱”。' },
    @{ File='chapter_9.rpy'; Start=296; End=453; Title='一男二女关系：共同交往、结婚证和隐瞒家长'; Note='三人正式确立关系，并讨论责任、婚姻登记和暂不告诉家长。' },
    @{ File='chapter_9.rpy'; Start=515; End=625; Title='共同生活：同居、家务、生育与性关系'; Note='一年后，三人讨论同居、贤妻良母、孩子以及进一步的亲密关系。' }
)

$controversyParts = [Collections.Generic.List[string]]::new()
$controversyParts.Add('《夏梦》关键争议原文')
$controversyParts.Add('')
$controversyParts.Add('说明：标题、出处和“编辑说明”由整理者添加；其后的剧情正文均按原始脚本提取，未作总结、润色或改写。')
$controversyParts.Add('')
$sceneEntryCount = 0

foreach ($scene in $sceneDefinitions) {
    $path = Join-Path $SourceDirectory $scene.File
    $entries = @(Get-StoryEntries -Path $path -FromLine $scene.Start -ToLine $scene.End)
    if ($entries.Count -eq 0) {
        throw "Controversy scene extracted no text: $($scene.Title)"
    }

    $controversyParts.Add(('【{0}】' -f $scene.Title))
    $controversyParts.Add(('出处：{0}，原文件约第 {1}-{2} 行' -f $scene.File, $scene.Start, $scene.End))
    $controversyParts.Add(('编辑说明：{0}' -f $scene.Note))
    $controversyParts.Add('')

    foreach ($entry in $entries) {
        $rendered = Format-StoryEntry $entry
        $controversyParts.Add($rendered)
        $controversyParts.Add('')
        $sceneEntryCount++
    }

    $controversyParts.Add('------------------------------------------------------------')
    $controversyParts.Add('')
}

while ($controversyParts.Count -gt 0 -and $controversyParts[$controversyParts.Count - 1] -eq '') {
    $controversyParts.RemoveAt($controversyParts.Count - 1)
}

$newLine = "`r`n"
$completeText = ($completeParts -join $newLine) + $newLine
$controversyText = ($controversyParts -join $newLine) + $newLine

if ($completeText -match '\{(?:tipid|w|nw)') {
    throw 'Unremoved Ren''Py text tags remain in the complete output.'
}
if ($completeText -match '(?m)^\s*(label|jump|call|scene|show|play|pause|hide)\b') {
    throw 'Ren''Py control or presentation commands remain in the complete output.'
}

foreach ($scene in $sceneDefinitions) {
    $path = Join-Path $SourceDirectory $scene.File
    $entries = @(Get-StoryEntries -Path $path -FromLine $scene.Start -ToLine $scene.End)
    foreach ($entry in $entries) {
        $rendered = Format-StoryEntry $entry
        if (-not $completeText.Contains($rendered)) {
            throw "Controversy text was not found in complete output: $($scene.Title), $($scene.File):$($entry.StartLine)"
        }
    }
}

$utf8Bom = [Text.UTF8Encoding]::new($true)
$completePath = Join-Path $OutputDirectory '夏梦_完整剧情原文.txt'
$controversyPath = Join-Path $OutputDirectory '夏梦_关键争议原文.txt'
[IO.File]::WriteAllText($completePath, $completeText, $utf8Bom)
[IO.File]::WriteAllText($controversyPath, $controversyText, $utf8Bom)

$result = [PSCustomObject]@{
    CompletePath              = $completePath
    CompleteBytes             = (Get-Item -LiteralPath $completePath).Length
    CompleteCharacters        = $completeText.Length
    CompleteVisibleEntries    = ($allEntriesByChapter.Values | ForEach-Object Count | Measure-Object -Sum).Sum
    ControversyPath           = $controversyPath
    ControversyBytes          = (Get-Item -LiteralPath $controversyPath).Length
    ControversyCharacters     = $controversyText.Length
    ControversyScenes         = $sceneDefinitions.Count
    ControversyVisibleEntries = $sceneEntryCount
}

$result | Format-List
}
catch {
    Write-Host ''
    Write-Host 'Build-StoryText.ps1 执行失败：' -ForegroundColor Red
    Write-Host ($_.Exception.ToString())
    if ($null -ne $_.InvocationInfo -and $_.InvocationInfo.PositionMessage) {
        Write-Host $_.InvocationInfo.PositionMessage
    }
    if ($env:SUMMERDREAM_STORY_LAUNCHER -ne 'cmd') {
        Read-Host '按 Enter 键退出' | Out-Null
    }
    exit 1
}
