import re
from dataclasses import dataclass, field
from typing import List, Tuple, Optional, Dict

def normalize_drug_name(name: str) -> str:
    """OCR 텍스트 전처리: 공백, 괄호, 특수문자 정규화"""
    if not name:
        return ""
    # 괄호 및 괄호 내용 제거/정리, 특수문자 제거, 소문자 변환
    text = re.sub(r'\(.*?\)', '', name)
    text = re.sub(r'\[.*?\]', '', text)
    text = re.sub(r'[^가-힣a-zA-Z0-9]', '', text)
    return text.strip().lower()

def get_ngrams(text: str, n: int = 3) -> List[str]:
    """n-gram 구하기 (문자열 길이가 n 미만인 경우 전체 문자열 단일 n-gram 반환)"""
    if len(text) < n:
        return [text] if text else []
    return [text[i:i+n] for i in range(len(text) - n + 1)]

def trigram_similarity(s1: str, s2: str) -> float:
    """Trigram (3-gram) Dice 계수 기반 유사도 산출 (0.0 ~ 1.0)"""
    norm1, norm2 = normalize_drug_name(s1), normalize_drug_name(s2)
    if not norm1 or not norm2:
        return 0.0
    if norm1 == norm2:
        return 1.0

    grams1 = get_ngrams(norm1, 3) + get_ngrams(norm1, 2)
    grams2 = get_ngrams(norm2, 3) + get_ngrams(norm2, 2)

    if not grams1 or not grams2:
        return 0.0

    counts1: Dict[str, int] = {}
    for g in grams1:
        counts1[g] = counts1.get(g, 0) + 1

    intersection = 0
    for g in grams2:
        if counts1.get(g, 0) > 0:
            intersection += 1
            counts1[g] -= 1

    total_grams = len(grams1) + len(grams2)
    return (2.0 * intersection) / total_grams

def levenshtein_distance(s1: str, s2: str) -> int:
    """Levenshtein 편집 거리 계산"""
    if len(s1) < len(s2):
        return levenshtein_distance(s2, s1)
    if len(s2) == 0:
        return len(s1)

    previous_row = range(len(s2) + 1)
    for i, c1 in enumerate(s1):
        current_row = [i + 1]
        for j, c2 in enumerate(s2):
            insertions = previous_row[j + 1] + 1
            deletions = current_row[j] + 1
            substitutions = previous_row[j] + (c1 != c2)
            current_row.append(min(insertions, deletions, substitutions))
        previous_row = current_row

    return previous_row[-1]

def levenshtein_similarity(s1: str, s2: str) -> float:
    """Levenshtein 거리 기반 정규화 유사도 산출 (0.0 ~ 1.0)"""
    norm1, norm2 = normalize_drug_name(s1), normalize_drug_name(s2)
    if not norm1 or not norm2:
        return 0.0
    if norm1 == norm2:
        return 1.0

    max_len = max(len(norm1), len(norm2))
    if max_len == 0:
        return 1.0
    dist = levenshtein_distance(norm1, norm2)
    return max(0.0, 1.0 - (dist / max_len))

def combined_similarity(s1: str, s2: str) -> float:
    """Trigram과 Levenshtein 유사도를 결합한 종합 유사도 산출"""
    norm1, norm2 = normalize_drug_name(s1), normalize_drug_name(s2)
    
    if norm1 and norm2 and (norm1 in norm2 or norm2 in norm1):
        coverage = min(len(norm1), len(norm2)) / max(len(norm1), len(norm2))
        return max(0.85, coverage)

    t_sim = trigram_similarity(norm1, norm2)
    l_sim = levenshtein_similarity(norm1, norm2)
    
    return 0.5 * t_sim + 0.5 * l_sim

@dataclass
class MatchResult:
    status: str                         # 'EXACT', 'HIGH', 'AMBIGUOUS', 'UNKNOWN'
    scanned_name: str
    best_matched_name: Optional[str]
    confidence: float
    candidates: List[Tuple[str, float]] = field(default_factory=list)

class DrugMatcher:
    def __init__(self, target_drug_names: Optional[List[str]] = None):
        self.target_drug_names = target_drug_names or []

    def set_target_drugs(self, drug_names: List[str]):
        self.target_drug_names = drug_names

    def match(
        self,
        scanned_name: str,
        high_threshold: float = 0.65,
        ambiguous_threshold: float = 0.35,
        top_k: int = 3
    ) -> MatchResult:
        """
        OCR 약품명 유사도 매칭 수행
        - high_threshold 이상: HIGH / EXACT 매칭 (자동 보정)
        - ambiguous_threshold ~ high_threshold: AMBIGUOUS (후보군 반환)
        - ambiguous_threshold 미만: UNKNOWN (확인 불가 - 가드레일)
        """
        norm_scanned = normalize_drug_name(scanned_name)
        if not norm_scanned:
            return MatchResult(
                status="UNKNOWN",
                scanned_name=scanned_name,
                best_matched_name=None,
                confidence=0.0,
                candidates=[]
            )

        scored_candidates: List[Tuple[str, float]] = []

        for official_name in self.target_drug_names:
            score = combined_similarity(scanned_name, official_name)
            scored_candidates.append((official_name, round(score, 4)))

        scored_candidates.sort(key=lambda x: x[1], reverse=True)

        if not scored_candidates:
            return MatchResult(
                status="UNKNOWN",
                scanned_name=scanned_name,
                best_matched_name=None,
                confidence=0.0,
                candidates=[]
            )

        best_name, best_score = scored_candidates[0]
        top_candidates = scored_candidates[:top_k]

        if best_score >= 0.95:
            return MatchResult(
                status="EXACT",
                scanned_name=scanned_name,
                best_matched_name=best_name,
                confidence=best_score,
                candidates=top_candidates
            )
        elif best_score >= high_threshold:
            return MatchResult(
                status="HIGH",
                scanned_name=scanned_name,
                best_matched_name=best_name,
                confidence=best_score,
                candidates=top_candidates
            )
        elif best_score >= ambiguous_threshold:
            return MatchResult(
                status="AMBIGUOUS",
                scanned_name=scanned_name,
                best_matched_name=best_name,
                confidence=best_score,
                candidates=top_candidates
            )
        else:
            return MatchResult(
                status="UNKNOWN",
                scanned_name=scanned_name,
                best_matched_name=None,
                confidence=best_score,
                candidates=top_candidates
            )
