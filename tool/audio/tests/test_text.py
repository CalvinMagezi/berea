import pytest

from text import bsb_verses, book_numbers, number_words, spoken_words, tokens


@pytest.mark.parametrize(
    "n, words",
    [
        (7, "SEVEN"),
        (38, "THIRTY EIGHT"),
        (40, "FORTY"),
        (153, "ONE HUNDRED FIFTY THREE"),
        (1000, "ONE THOUSAND"),
        (144_000, "ONE HUNDRED FORTY FOUR THOUSAND"),
        (2_300_005, "TWO MILLION THREE HUNDRED THOUSAND FIVE"),
    ],
)
def test_number_words(n, words):
    assert number_words(n) == words.split()


@pytest.mark.parametrize(
    "token, words",
    [
        # Each case is a real pattern from the pilot chapters (John, Psalms 1-30).
        ("God\u2019s", ["GOD'S"]),
        ("him.\u2019", ["HIM"]),
        ("\u2018Rabbi,", ["RABBI"]),
        ("\u201cTruly,", ["TRULY"]),
        ("went\u2014not", ["WENT", "NOT"]),
        ("place\u2014", ["PLACE"]),
        ("thirty-eight", ["THIRTY", "EIGHT"]),
        ("father-in-law", ["FATHER", "IN", "LAW"]),
        ("153,", ["ONE", "HUNDRED", "FIFTY", "THREE"]),
        ("1,000", ["ONE", "THOUSAND"]),
        ("(Selah)", ["SELAH"]),
        ("LORD!", ["LORD"]),
        ("\u2014", []),
    ],
)
def test_spoken_words(token, words):
    assert spoken_words(token) == words


def test_tokens_split_on_any_whitespace_like_the_app():
    assert tokens(" In the\tbeginning\u00a0was ") == ["In", "the", "beginning", "was"]


SAMPLE = (
    "\ufeffThe Holy Bible, Berean Standard Bible\t\n"
    "\t\n"
    "Verse\tBerean Standard Bible\n"
    "Genesis 1:1\tIn the beginning God created the heavens and the earth. \n"
    "Psalm 3:2\tMany say of me, \u201cGod will not deliver him.\u201d Selah\n"
    "\n"
    "John 3:16\tFor God so loved the world\n"
)


def test_bsb_verses_matches_the_app_importer():
    verses = bsb_verses(SAMPLE)
    assert verses[("Genesis", 1, 1)] == "In the beginning God created the heavens and the earth."
    assert list(verses)[1] == ("Psalm", 3, 2)
    assert book_numbers(verses) == {"Genesis": 1, "Psalm": 2, "John": 3}


def test_bsb_verses_refuses_a_file_without_a_header():
    with pytest.raises(ValueError):
        bsb_verses("Genesis 1:1\tIn the beginning")
