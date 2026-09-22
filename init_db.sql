-- 1. 유사도 검색을 위한 pg_trgm 확장 활성화
CREATE EXTENSION IF NOT EXISTS pg_trgm;

-- 2. 의약품 마스터 테이블
CREATE TABLE IF NOT EXISTS drug_master (
    item_seq VARCHAR(20) PRIMARY KEY,              -- 품목기준코드
    item_name VARCHAR(255) NOT NULL,               -- 제품명
    item_name_clean VARCHAR(255) NOT NULL,         -- 검색용 정규화 명칭
    entp_name VARCHAR(100),                        -- 제약사명
    ingredient_name TEXT,                          -- 주성분명
    form_type VARCHAR(50),                         -- 제형 (시럽제, 정제 등)
    liquid_concentration_mg_per_ml NUMERIC(8, 2),  -- 시럽제 ml당 성분 함량(mg)
    
    -- e약은요 쉬운 해설 텍스트
    efficacy_summary TEXT,                         -- 효능/효과
    usage_summary TEXT,                            -- 복약 방법
    warning_summary TEXT,                          -- 주의사항
    side_effects_summary TEXT,                     -- 부작용
    storage_method TEXT,                           -- 보관법 (실온/냉장 등)
    
    -- 약품 분류 플래그
    is_antibiotic BOOLEAN DEFAULT FALSE,           -- 항생제
    is_steroid BOOLEAN DEFAULT FALSE,              -- 스테로이드
    is_antipyretic BOOLEAN DEFAULT FALSE,          -- 해열진통제
    is_antihistamine BOOLEAN DEFAULT FALSE,        -- 항히스타민제
    
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- OCR 약품명 오타/유사도 검색 전용 Trigram 인덱스
CREATE INDEX IF NOT EXISTS idx_drug_name_trgm 
ON drug_master USING GIN (item_name_clean gin_trgm_ops);

-- 3. 소아/성인 용량 기준 룰셋 테이블
CREATE TABLE IF NOT EXISTS drug_dosage_rules (
    rule_id SERIAL PRIMARY KEY,
    item_seq VARCHAR(20) REFERENCES drug_master(item_seq) ON DELETE CASCADE,
    ingredient_name VARCHAR(100) NOT NULL,
    
    -- 소아 기준 (체중 기반 mg/kg)
    child_single_dose_min_mg_kg NUMERIC(6, 3), -- 1회 최소 권장량
    child_single_dose_max_mg_kg NUMERIC(6, 3), -- 1회 최대 권장량
    child_daily_dose_max_mg_kg NUMERIC(6, 3),  -- 1일 최대 한도량
    child_min_age_months INT DEFAULT 0,        -- 투약 가능 최소 월령
    
    -- 성인 기준 (1일 상한선 mg)
    adult_daily_dose_max_mg NUMERIC(8, 2),
    guidance_notes TEXT                        -- 주의 가이드 문구
);