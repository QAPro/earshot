"""Checks for the renderer's text rules. Run: python render/test_earshot_text.py"""
import earshot_text as et

CAST = """---
voices:
  Narrator: Michael
  CV: George | a dry man
  Jo: Heart
---
CV and Jo were alone with the fire.
Jo: That was fast.
CV: Yeah, well. Kelly's been angry for a decade and somebody finally argued back.
[pause 1s]
"""


def test_every_sentence_of_a_line_keeps_its_speaker():
    # Phil, 2026-10-27: the second sentence of CV's line came out in the narrator's voice.
    segs = et.segment(CAST)
    cv = [s for s in segs if s.voice == "bm_george"]
    assert [s.text for s in cv] == ["Yeah, well.",
                                    "Kelly's been angry for a decade and somebody finally argued back."]
    assert all(s.speaker == "CV" for s in cv)
    assert cv[0].label == "CV" and cv[1].label is None  # shown once in the reader
    assert segs[0].speaker is None  # narrator line


def test_descriptions_and_pauses():
    segs = et.segment(CAST)
    assert all(s.description == "a dry man" for s in segs if s.speaker == "CV")
    assert segs[-1].pause_ms == 1000 and segs[-1].text == ""


if __name__ == "__main__":
    for name, fn in list(globals().items()):
        if name.startswith("test_"):
            fn()
            print("ok", name)
