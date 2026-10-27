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


def test_inline_pauses():
    doc = "---\nvoices:\n  Narrator: George\n  Jo: Heart\n---\nJo: Yeah, well. [pause 2s] Fine.\n[pause 500ms] The door shut.\n"
    segs = et.segment(doc)
    assert [s.text for s in segs] == ["Yeah, well.", "", "Fine.", "", "The door shut."]
    assert segs[1].pause_ms == 2000 and segs[3].pause_ms == 500
    assert segs[0].label == "Jo" and segs[2].label is None and segs[2].speaker == "Jo"
    assert segs[4].speaker is None
    plain = et.segment("First part. [Pause 1.5s] Second part.\n\n[pause 3s]")
    assert [(s.text, s.pause_ms) for s in plain] == [("First part.", 0), ("", 1500), ("Second part.", 0), ("", 3000)]


def test_pause_spellings():
    for tag, ms in [("[pause 1 sec]", 1000), ("[Pause: 2 seconds]", 2000), ("[pause 250 milliseconds]", 250), ("[pause 1.5]", 1500)]:
        segs = et.segment(f"Before. {tag} After.")
        assert [(x.text, x.pause_ms) for x in segs] == [("Before.", 0), ("", ms), ("After.", 0)], tag


if __name__ == "__main__":
    for name, fn in list(globals().items()):
        if name.startswith("test_"):
            fn()
            print("ok", name)
