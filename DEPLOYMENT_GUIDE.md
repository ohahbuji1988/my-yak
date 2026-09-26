# [Kidipedia] 키디피디아 초고속 올인원 클라우드 배포 가이드

본 프로젝트는 **FastAPI 단일 서버가 Flutter Web(PWA) 프론트엔드를 함께 서빙**하도록 구축되어 있어, 도메인 1개만으로 백엔드(AI OCR/DUR/의사Q&A)와 프론트엔드를 한 번에 배포할 수 있습니다.

---

## 🚀 추천 배포 플랫폼 1위: Render.com (가장 간단 & 무료 티어 지원)

1. **GitHub에 코드 푸시**
   ```bash
   git add .
   git commit -m "feat: Kidipedia all-in-one cloud web deployment"
   git push origin main
   ```

2. **Render.com 접속 및 로그인**
   * [https://render.com](https://render.com) 접속 후 GitHub 계정으로 로그인

3. **New Web Service 생성**
   * **[New +]** 버튼 클릭 ➔ **[Web Service]** 선택
   * 본인의 `my-yak-pjt` (또는 `kidipedia`) 저장소(Repository) 선택
   * 설정값 입력:
     * **Name**: `kidipedia` (원하는 이름)
     * **Runtime**: `Python 3` (또는 `Docker`)
     * **Build Command**: `pip install -r requirements.txt`
     * **Start Command**: `uvicorn main:app --host 0.0.0.0 --port $PORT`
     * **Plan**: Free ($0/month)

4. **환경 변수(Environment Variables) 등록**
   * `GEMINI_API_KEY`: 본인의 Gemini API 키 입력

5. **배포 완료!**
   * 약 1~2분 후 `https://kidipedia.onrender.com` 과 같은 무료 글로벌 HTTPS 주소가 생성됩니다.

---

## 🚀 대안 플랫폼: Railway / Fly.io / Google Cloud Run

* **Railway**: GitHub 연동 후 바로 `Deploy Now` 누르면 `Dockerfile`을 자동 감지하여 즉시 배포됩니다.
* **Google Cloud Run**: GCP 콘솔에서 Cloud Run 서비스 생성 후 컨테이너 자동 빌드로 무제한 확장 가능.

---

## 📱 스마트폰에 진짜 앱처럼 설치하는 방법 (PWA 가이드)

1. 배포된 웹 주소(예: `https://kidipedia.onrender.com`)를 스마트폰 브라우저로 엽니다.
2. **아이폰 (Safari)**:
   * 하단 중앙 **[공유(내보내기) 버튼 📤]** ➔ **[홈 화면에 추가]** 클릭
3. **갤럭시 / 안드로이드 (Chrome / 삼성인터넷)**:
   * 브라우저 우측 상단 **[메뉴(점 3개)]** ➔ **[앱 설치]** 또는 **[홈 화면에 추가]** 클릭
4. 바탕화면에 **[키디피디아]** 앱 아이콘이 생성되며, 터치 시 주소창 없는 전체 화면의 진짜 네이티브 앱으로 실행됩니다!
