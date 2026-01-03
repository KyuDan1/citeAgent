# CiteAgent - Native macOS App

**자동 논문 인용 도구 for Overleaf**

Python 기반 CiteAgent를 macOS App Store에 올릴 수 있는 네이티브 Safari Extension 앱으로 전환한 버전입니다.

## 📋 개요

CiteAgent는 Overleaf에서 LaTeX 문서를 작성할 때 자동으로 논문을 검색하고 인용을 추가해주는 도구입니다.

### 주요 기능

- 🎯 **5cm 크기의 떠있는 네비게이터**: 항상 위에 표시되는 작은 컨트롤 패널
- 🔍 **자동 논문 검색**: Semantic Scholar API를 통한 학술 논문 검색
- 🤖 **AI 기반 인용 추가**: Gemini 또는 Upstage LLM을 사용한 스마트 인용
- 📝 **Overleaf 통합**: Safari Extension을 통한 실시간 에디터 제어
- 🔐 **App Store 호환**: 샌드박스 환경에서 안전하게 동작

## 🏗️ 아키텍처

### Python (기존) → Swift + Safari Extension (신규)

| 구성요소 | 기존 (Python) | 신규 (macOS Native) |
|---------|--------------|-------------------|
| UI | 커맨드라인 | **FloatingNavigatorView** (SwiftUI) |
| Overleaf 제어 | Selenium + AppleScript | **Safari Extension content.js** |
| 논문 검색 | paper_search.py | **PaperSearchService.swift** |
| LLM 통합 | citation_agent.py | **CitationAgentService.swift** |
| 통신 | 직접 브라우저 제어 | **Native Messaging** (Extension ↔ App) |

## 📂 프로젝트 구조

```
CiteAgent/
├── macOS (App)/
│   ├── AppDelegate.swift              # 앱 진입점 및 플로팅 윈도우 생성
│   ├── FloatingNavigatorView.swift    # 메인 UI (5cm 네비게이터)
│   └── SettingsView.swift             # API 키 설정 화면
│
├── Shared (App)/
│   ├── Models.swift                   # 데이터 모델 (Paper, AppConfig)
│   ├── PaperSearchService.swift       # Semantic Scholar API 클라이언트
│   ├── CitationAgentService.swift     # LLM 통합 및 인용 로직
│   └── ViewController.swift           # 기존 WebView (확장 설치용)
│
├── Shared (Extension)/
│   ├── SafariWebExtensionHandler.swift # Native 메시지 처리
│   └── Resources/
│       ├── manifest.json              # Extension 설정 (Overleaf 권한)
│       ├── content.js                 # Overleaf 에디터 제어 (Python JS 코드 이식)
│       └── background.js              # 메시지 라우팅
│
└── README.md                          # 이 파일
```

## 🚀 빌드 및 실행

### 1. Xcode에서 프로젝트 열기

```bash
open /Users/kyudan/Desktop/CiteAgent/CiteAgent.xcodeproj
```

### 2. 파일 추가

Xcode에서 다음 파일들을 각 타겟에 추가해야 합니다:

**macOS (App) 타겟에 추가:**
- `FloatingNavigatorView.swift`
- `SettingsView.swift`
- `Models.swift`
- `PaperSearchService.swift`
- `CitationAgentService.swift`

**Extension 타겟에 추가 (이미 있는 경우 업데이트):**
- `content.js`
- `background.js`
- `manifest.json`
- `SafariWebExtensionHandler.swift`

### 3. 빌드 및 실행

1. Xcode에서 타겟을 **macOS (App)**으로 선택
2. ⌘R (Run) 실행
3. 앱이 실행되면 플로팅 네비게이터 윈도우가 화면 우측 상단에 나타납니다

### 4. Safari Extension 활성화

1. Safari 열기 → 환경설정 → 확장 프로그램
2. "CiteAgent Extension" 찾아서 활성화
3. Overleaf 페이지에서 권한 허용

## ⚙️ 설정

### API 키 설정

1. 플로팅 네비게이터에서 ⚙️ (톱니바퀴) 아이콘 클릭
2. 필요한 API 키 입력:
   - **Gemini API**: https://aistudio.google.com/apikey
   - **Upstage API**: https://console.upstage.ai/
   - **Semantic Scholar API** (선택사항): https://www.semanticscholar.org/product/api

### 설정 항목

- **LLM Provider**: Gemini 또는 Upstage 선택
- **Temperature**: 0.0 ~ 1.0 (기본: 0.3)
- **Max Papers per Search**: 검색 결과 개수 (기본: 5)
- **Min Citation Count**: 최소 인용 횟수 필터 (기본: 10)

## 📖 사용 방법

### 1. Overleaf에서 사용

1. Safari에서 Overleaf 프로젝트 열기
2. LaTeX 에디터에서 인용이 필요한 텍스트 선택
3. 플로팅 네비게이터에서 **"Add Citations"** 버튼 클릭
4. AI가 자동으로 논문을 검색하고 `\cite{}` 태그 추가
5. BibTeX 항목이 자동으로 `.bib` 파일에 추가됨

### 2. 작동 흐름

```
[사용자] 텍스트 선택
    ↓
[플로팅 앱] "Add Citations" 클릭
    ↓
[Safari Extension] content.js가 선택 텍스트 읽기
    ↓
[Native App] CitationAgentService가 LLM API 호출
    ↓
[LLM] 인용이 필요한 부분 식별
    ↓
[PaperSearchService] Semantic Scholar에서 논문 검색
    ↓
[Native App] BibTeX 생성 및 텍스트 수정
    ↓
[Safari Extension] Overleaf 에디터에 적용
```

## 🔧 주요 구현 세부사항

### Python → Swift 변환 매핑

#### 1. Overleaf 에디터 제어

**Python (기존):**
```python
# safari_applescript_controller.py
js_code = """
var elem = window.editor || document.querySelector('.cm-editor');
if (elem) {
    var cmView = elem.CodeMirror || elem.cmView || elem.cm;
    if (cmView && cmView.view) {
        return cmView.view.state.doc.toString();
    }
}
"""
result = self._run_javascript(js_code)
```

**JavaScript (신규):**
```javascript
// content.js
function getEditorContent() {
    const editorObj = getOverleafEditor();
    if (editorObj.type === 'codemirror6') {
        return editorObj.editor.state.doc.toString();
    }
    return null;
}
```

#### 2. 논문 검색 API

**Python (기존):**
```python
# paper_search.py
response = self.session.get(search_url, params=params, timeout=15)
data = response.json()
papers = [Paper(...) for item in data["data"]]
```

**Swift (신규):**
```swift
// PaperSearchService.swift
let (data, response) = try await session.data(for: request)
let searchResponse = try JSONDecoder().decode(SemanticScholarResponse.self, from: data)
let papers = searchResponse.data.compactMap { ... }
```

#### 3. LLM API 호출

**Python (기존):**
```python
# citation_agent.py
response = chat.send_message(user_message, tools=tools)
```

**Swift (신규):**
```swift
// CitationAgentService.swift
let (data, response) = try await URLSession.shared.data(for: request)
let geminiResponse = try JSONDecoder().decode(GeminiResponse.self, from: data)
```

### Native Messaging 구조

```
┌─────────────────────┐
│  FloatingNavigator  │ (SwiftUI)
│  "Add Citations"    │
└──────────┬──────────┘
           │ 1. 버튼 클릭
           ↓
┌─────────────────────┐
│  Safari Extension   │
│  background.js      │
└──────────┬──────────┘
           │ 2. sendNativeMessage()
           ↓
┌─────────────────────────────┐
│ SafariWebExtensionHandler   │ (Swift)
│ handleProcessCitation()     │
└──────────┬──────────────────┘
           │ 3. CitationAgentService
           ↓
┌─────────────────────┐
│  Gemini/Upstage API │
│  Semantic Scholar   │
└──────────┬──────────┘
           │ 4. 응답
           ↓
┌─────────────────────┐
│  content.js         │
│  replaceSelectedText│
└─────────────────────┘
```

## 🎨 UI 특징

### 플로팅 네비게이터 (5cm 크기)

- **크기**: 240x180px (약 5cm × 4cm)
- **위치**: 화면 우측 상단
- **스타일**: `.floating` 레벨 (항상 위에 표시)
- **특징**:
  - 모든 Space에서 표시 (`.canJoinAllSpaces`)
  - 풀스크린 모드에서도 표시 (`.fullScreenAuxiliary`)
  - 비활성화 패널 (다른 앱 사용 중에도 항상 보임)

### 상태 표시

- 🟢 **Ready**: 대기 중
- 🟡 **Processing**: 처리 중 (Spinner 표시)
- ⚙️ **Settings**: 설정 버튼
- 🧭 **Safari Extension**: Safari 환경설정 열기

## 📦 App Store 배포 준비

### 1. Bundle Identifier 설정

Xcode에서:
- **앱**: `kyudan.CiteAgent`
- **Extension**: `kyudan.CiteAgent.Extension`

### 2. Capabilities 추가

- ☑️ App Sandbox
- ☑️ Network Client (API 호출용)
- ☑️ Safari Extension

### 3. Privacy 설명 추가 (Info.plist)

```xml
<key>NSNetworkClientDescription</key>
<string>CiteAgent needs network access to search academic papers and call LLM APIs for citation generation.</string>
```

### 4. App Store 제출

1. Archive 생성 (Product → Archive)
2. Organizer에서 "Distribute App" 선택
3. App Store Connect 업로드
4. 심사 제출

## 🔍 디버깅

### Safari Extension 디버깅

1. Safari → Develop → "Your Computer Name" → CiteAgent Extension
2. Web Inspector에서 console 로그 확인

### macOS 앱 디버깅

- Xcode Console에서 `os_log` 메시지 확인
- `[CiteAgent]` 태그로 필터링

## 📝 알려진 제한사항

1. **Function Calling 미구현**: 현재는 단순 프롬프트 방식. 향후 Gemini/Upstage의 function calling 구현 필요
2. **전체 문서 처리**: 현재는 선택 텍스트만 처리. 전체 문서 처리 기능 추가 예정
3. **오프라인 지원 없음**: 모든 기능이 API 호출 필요

## 🛣️ 향후 개발 계획

- [ ] Gemini/Upstage function calling 완전 구현
- [ ] 전체 문서 자동 처리 모드
- [ ] 키보드 단축키 지원 (⌘⇧C)
- [ ] 커스텀 프롬프트 템플릿
- [ ] 인용 스타일 선택 (\citep, \citet, \cite)
- [ ] 로컬 논문 데이터베이스 캐싱

## 📄 라이선스

이 프로젝트는 원본 Python CiteAgent를 기반으로 합니다.

## 🙏 감사

- **Semantic Scholar**: 논문 검색 API 제공
- **Google Gemini**: LLM API
- **Upstage**: 한국어 최적화 LLM

---

**Made with ❤️ for LaTeX writers**
