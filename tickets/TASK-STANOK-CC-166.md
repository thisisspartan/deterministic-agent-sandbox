# TASK-STANOK-CC-166: Smoke ticket — machine run (third smoke)

impl: src/smoke_text.py
test: tests/smoke_text_test.py
run.sh: exists

## Задача
1. Создать `src/smoke_text.py` — модуль с двумя чистыми функциями:
   - `word_count(s)` — количество слов в строке (разделители —
     пробельные символы; пустая строка и строка из одних пробелов → 0).
   - `caesar_shift(text, k)` — сдвиг латинских букв a–z/A–Z на `k`
     позиций по кругу (k может быть отрицательным и больше 26);
     все не-буквенные символы остаются без изменений.
2. Создать `tests/smoke_text_test.py` (pytest):
   - `word_count`: `""` → 0; `"   "` → 0; `"a b c"` → 3;
     `"  hello,   world  "` → 2.
   - `caesar_shift`: `("abc", 1)` → `"bcd"`; `("xyz", 3)` → `"abc"`;
     `("Abc", -1)` → `"Zab"`; `("a1b", 26)` → `"a1b"`;
     `("Hello, World!", 13)` → `"Uryyb, Jbeyq!"`.

## Gate / Проверка
`pytest tests/smoke_text_test.py`
