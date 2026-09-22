FROM python:3.11-slim

WORKDIR /app

# 필수 의존성 설치
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# 소스코드 및 사전 빌드된 Flutter Web(build/web) 복사
COPY . .

ENV PORT=8000
EXPOSE 8000

# 클라우드 호스팅 PORT 환경변수 지원
CMD ["sh", "-c", "uvicorn main:app --host 0.0.0.0 --port "]
