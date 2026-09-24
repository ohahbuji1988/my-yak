import os
import sqlite3
import asyncio
from typing import Optional, List, Dict, Any

# PostgreSQL 연결 정보 (환경변수 기본값)
PG_HOST = os.getenv("POSTGRES_HOST", "localhost")
PG_PORT = int(os.getenv("POSTGRES_PORT", 5432))
PG_DB = os.getenv("POSTGRES_DB", "my_yak_db")
PG_USER = os.getenv("POSTGRES_USER", "postgres")
PG_PASS = os.getenv("POSTGRES_PASSWORD", "postgres")

class DatabaseRepository:
    """PostgreSQL (pg_trgm) 및 SQLite 백업 호환 DB 레포지토리"""
    
    def __init__(self, db_path: str = "my_yak_local.db"):
        self.db_path = db_path
        self._init_sqlite_mock_db()

    def _init_sqlite_mock_db(self):
        """SQLite 오프라인/테스트용 데이터베이스 및 초기 시드 데이터 구축"""
        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()
        
        cursor.execute("""
        CREATE TABLE IF NOT EXISTS drug_master (
            item_seq TEXT PRIMARY KEY,
            item_name TEXT NOT NULL,
            item_name_clean TEXT NOT NULL,
            entp_name TEXT,
            ingredient_name TEXT,
            form_type TEXT,
            liquid_concentration_mg_per_ml REAL,
            efficacy_summary TEXT,
            usage_summary TEXT,
            warning_summary TEXT,
            side_effects_summary TEXT,
            storage_method TEXT,
            is_antibiotic INTEGER DEFAULT 0,
            is_steroid INTEGER DEFAULT 0,
            is_antipyretic INTEGER DEFAULT 0,
            is_antihistamine INTEGER DEFAULT 0
        )
        """)

        # 초기 시드 약품 데이터 삽입
        seed_drugs = [
            ("200808948", "맥시부펜시럽", "맥시부펜시럽", "한미약품", "덱시부프로펜", "시럽제", 12.0, "해열진통소염", "용량 준수", "위장장애 주의", "부작용 알림", "실온보관", 0, 0, 1, 0),
            ("200401824", "아모크라네오시럽", "아모크라네오시럽", "한미약품", "아목시실린/클라불란산", "시럽제", 50.0, "항생제", "기한 준수", "설사 주의", "발진", "냉장보관", 1, 0, 0, 0),
            ("199901533", "코미시럽", "코미시럽", "코오롱제약", "트리프로리딘", "시럽제", 2.5, "비염/알레르기", "용량 준수", "졸림 주의", "구갈", "실온보관", 0, 0, 0, 1),
            ("199401777", "타이레놀8시간이알서방정", "타이레놀8시간이알서방정", "한국존슨앤드존슨", "아세트아미노펜", "정제", 650.0, "해열진통", "8시간 간격", "간독성 주의", "발진", "실온보관", 0, 0, 1, 0),
            ("199100868", "무코스타정", "무코스타정", "한국오츠카제약", "레바미피드", "정제", 100.0, "위점막보호", "1일 3회", "위염 완화", "구토", "실온보관", 0, 0, 0, 0),
            ("200806456", "코싹엘정", "코싹엘정", "한미약품", "레보세티리진/슈도에페드린", "정제", 5.0, "비염 완화", "1일 2회", "졸림 및 불면", "두통", "실온보관", 0, 0, 0, 1),
            ("200003058", "웅스코민정", "웅스코민정", "대웅제약", "부틸스코폴라민", "정제", 10.0, "위장관 복통 완화", "필요시 복용", "시야장애 주의", "변비", "실온보관", 0, 0, 0, 0),
            ("200401825", "엘코스텐캡슐", "엘코스텐캡슐", "대원제약", "에르도스테인", "캡슐제", 300.0, "기관지 가래 용해/배출", "1회 1캡슐, 1일 2~3회", "위장장애 주의", "발진", "실온보관", 0, 0, 0, 0)
        ]

        cursor.executemany("""
        INSERT OR IGNORE INTO drug_master (
            item_seq, item_name, item_name_clean, entp_name, ingredient_name,
            form_type, liquid_concentration_mg_per_ml, efficacy_summary, usage_summary,
            warning_summary, side_effects_summary, storage_method, is_antibiotic,
            is_steroid, is_antipyretic, is_antihistamine
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """, seed_drugs)

        conn.commit()
        conn.close()

    async def get_all_drug_names(self) -> List[str]:
        """DB에 등록된 전체 정규화 약품명 목록 반환"""
        loop = asyncio.get_event_loop()
        def _fetch():
            conn = sqlite3.connect(self.db_path)
            cursor = conn.cursor()
            cursor.execute("SELECT item_name FROM drug_master")
            rows = cursor.fetchall()
            conn.close()
            return [r[0] for r in rows]
        return await loop.run_in_executor(None, _fetch)

    async def get_drug_by_name(self, drug_name: str) -> Optional[Dict[str, Any]]:
        """약품명 기준 상세 정보 조회"""
        loop = asyncio.get_event_loop()
        def _fetch():
            conn = sqlite3.connect(self.db_path)
            cursor = conn.cursor()
            cursor.execute("SELECT * FROM drug_master WHERE item_name = ? OR item_name_clean = ?", (drug_name, drug_name))
            row = cursor.fetchone()
            conn.close()
            if not row:
                return None
            return {
                "item_seq": row[0],
                "item_name": row[1],
                "item_name_clean": row[2],
                "entp_name": row[3],
                "ingredient_name": row[4],
                "form_type": row[5],
                "liquid_concentration_mg_per_ml": row[6],
                "efficacy_summary": row[7],
                "usage_summary": row[8],
                "warning_summary": row[9],
                "side_effects_summary": row[10],
                "storage_method": row[11],
                "is_antibiotic": bool(row[12]),
                "is_steroid": bool(row[13]),
                "is_antipyretic": bool(row[14]),
                "is_antihistamine": bool(row[15])
            }
        return await loop.run_in_executor(None, _fetch)

db_repo = DatabaseRepository()
