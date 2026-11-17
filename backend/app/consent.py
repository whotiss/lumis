"""What users agree to before using Lumis, in English and Malay. The app shows this text; it holds no copy.

Why it is written this way (Malaysia's Personal Data Protection Act 2010, as amended in 2024):
  - Health information is "sensitive personal data", which needs the person's EXPLICIT consent: a required
    tick box, never a pre-ticked one or "by using this app you agree".
  - The notice must be given in Bahasa Malaysia and English.
  - Photos leave Malaysia (server in Singapore; Anthropic in the United States for the skin check). Explicit
    consent after a written notice of who receives them and why is one of the lawful bases for that transfer.
  - People must be told how to access and correct their data and how to withdraw consent.
Anthropic facts checked on 2026-11-17: API inputs are not used for training (Commercial Terms, section B) and are
deleted within 30 days, or kept up to 2 years if flagged by its safety systems (Anthropic privacy center).

CHANGING THE TEXT: any change to what a person agrees to needs a new CONSENT_VERSION. Every user is then asked
to agree again before their next screening. tests/test_consent.py fails if the text changes without a new version.
"""
from __future__ import annotations

CONSENT_VERSION = "2026-11-17.2"     # .2: Claude also describes the photo (Phase 5)
LANGUAGES = ("en", "ms")

_TEXT = {
    "en": {
        "title": "Before you use Lumis",
        "sections": [
            {"heading": "What Lumis is",
             "body": "Lumis is a screening aid built as a final-year student project at Sunway University. It uses "
                     "AI to suggest which of five skin conditions (acne, eczema, psoriasis, scabies and fungal "
                     "infection) a photo looks most like. It is not a medical diagnosis and does not replace a "
                     "doctor. It can be wrong, especially with photos unlike the ones it learned from. Lumis is for "
                     "people aged 18 and over."},
            {"heading": "What happens to your photo",
             "body": "When you do a screening, your photo is sent over an encrypted connection to Lumis's server in "
                     "Singapore (Google Cloud), where the Lumis model analyzes it. The photo is also sent to "
                     "Anthropic, an AI company in the United States, whose Claude model checks that the photo shows "
                     "skin and describes what it can see, to help explain your result. Anthropic does not use it "
                     "to train its models and deletes it within 30 days, unless its "
                     "safety systems flag it, in which case it may be kept for up to 2 years. Lumis keeps your "
                     "photo only if you turn on \"Keep my photos\" below."},
            {"heading": "What Lumis keeps",
             "body": "Your email address, and your password in a securely scrambled form (a hash). For each "
                     "screening: the result (the condition, the confidence and the advice), your answers about "
                     "your symptoms, the date and the model version. This is health information. It is kept in a "
                     "database in Singapore (Neon) until you delete it. If you turn on \"Keep my photos\", your "
                     "photos are kept in private storage in Singapore (Google Cloud) until you delete them. If you "
                     "turn on location, it is used only to sort clinics by distance, and it is not stored."},
            {"heading": "What Lumis does not do",
             "body": "No ads. Your data is not sold or shared with anyone other than the services named above. "
                     "Your photos and results are not used to train the Lumis model. Results may be counted in "
                     "anonymous totals for the project report (for example, how many screenings were "
                     "inconclusive)."},
            {"heading": "Your choices and rights",
             "body": "You can see and delete any screening in History. You can delete your account and everything "
                     "with it in Settings, which also withdraws your consent. You can turn photo storage and "
                     "location on or off at any time. Under Malaysia's Personal Data Protection Act 2010 you have "
                     "the right to access and correct your personal data. To ask for a copy of your data or ask a "
                     "question, contact {contact}."},
        ],
        "items": {
            "processing": "I agree that Lumis may process my photos and health information as described above, "
                          "including sending my photos to Lumis's server in Singapore and to Anthropic in the "
                          "United States.",
            "adult": "I am 18 or older.",
            "storage": "Keep my photos so I can see them in my history.",
            "location": "Use my location to find nearby clinics.",
        },
    },
    # Drafted by Claude for the project; to be checked by a fluent Malay speaker before real users see it.
    "ms": {
        "title": "Sebelum anda menggunakan Lumis",
        "sections": [
            {"heading": "Apakah Lumis",
             "body": "Lumis ialah alat saringan yang dibina sebagai projek tahun akhir pelajar di Sunway University. "
                     "Ia menggunakan AI untuk mencadangkan keadaan kulit yang paling hampir dengan foto anda, "
                     "daripada lima keadaan (jerawat, ekzema, psoriasis, kudis buta dan jangkitan kulat). Ia bukan "
                     "diagnosis perubatan dan tidak menggantikan doktor. Ia boleh tersilap, terutamanya dengan foto "
                     "yang berbeza daripada foto yang digunakan untuk melatihnya. Lumis adalah untuk mereka yang "
                     "berumur 18 tahun ke atas."},
            {"heading": "Apa yang berlaku kepada foto anda",
             "body": "Apabila anda membuat saringan, foto anda dihantar melalui sambungan yang disulitkan ke pelayan "
                     "Lumis di Singapura (Google Cloud), di mana model Lumis menganalisisnya. Foto itu juga "
                     "dihantar kepada Anthropic, sebuah syarikat AI di Amerika Syarikat, yang model Claudenya "
                     "memeriksa bahawa foto itu menunjukkan kulit dan menerangkan apa yang dapat dilihat, untuk "
                     "membantu menjelaskan keputusan anda. Anthropic tidak menggunakannya untuk melatih "
                     "modelnya dan memadamkannya dalam tempoh 30 hari, kecuali jika sistem keselamatannya "
                     "menandakannya, dan dalam keadaan itu ia boleh disimpan sehingga 2 tahun. Lumis menyimpan "
                     "foto anda hanya jika anda menghidupkan \"Simpan foto saya\" di bawah."},
            {"heading": "Apa yang disimpan oleh Lumis",
             "body": "Alamat e-mel anda, dan kata laluan anda dalam bentuk yang dikodkan secara selamat (hash). Bagi "
                     "setiap saringan: keputusannya (keadaan, tahap keyakinan dan nasihat), jawapan anda tentang "
                     "simptom, tarikh dan versi model. Ini ialah maklumat kesihatan. Ia disimpan dalam pangkalan "
                     "data di Singapura (Neon) sehingga anda memadamkannya. Jika anda menghidupkan \"Simpan foto "
                     "saya\", foto anda disimpan dalam storan peribadi di Singapura (Google Cloud) sehingga anda "
                     "memadamkannya. Jika anda menghidupkan lokasi, lokasi anda digunakan hanya untuk menyusun "
                     "klinik mengikut jarak, dan ia tidak disimpan."},
            {"heading": "Apa yang tidak dilakukan oleh Lumis",
             "body": "Tiada iklan. Data anda tidak dijual atau dikongsi dengan sesiapa selain perkhidmatan yang "
                     "dinamakan di atas. Foto dan keputusan anda tidak digunakan untuk melatih model Lumis. "
                     "Keputusan boleh dikira dalam jumlah tanpa nama untuk laporan projek (contohnya, berapa banyak "
                     "saringan yang tidak muktamad)."},
            {"heading": "Pilihan dan hak anda",
             "body": "Anda boleh melihat dan memadamkan mana-mana saringan dalam Sejarah. Anda boleh memadamkan "
                     "akaun anda dan semua data bersamanya dalam Tetapan; ini juga menarik balik persetujuan anda. "
                     "Anda boleh menghidupkan atau mematikan penyimpanan foto dan lokasi pada bila-bila masa. Di "
                     "bawah Akta Perlindungan Data Peribadi 2010, anda berhak untuk mengakses dan membetulkan data "
                     "peribadi anda. Untuk meminta salinan data anda atau bertanya soalan, hubungi {contact}."},
        ],
        "items": {
            "processing": "Saya bersetuju bahawa Lumis boleh memproses foto dan maklumat kesihatan saya seperti yang "
                          "diterangkan di atas, termasuk menghantar foto saya ke pelayan Lumis di Singapura dan "
                          "kepada Anthropic di Amerika Syarikat.",
            "adult": "Saya berumur 18 tahun atau lebih.",
            "storage": "Simpan foto saya supaya saya boleh melihatnya dalam sejarah saya.",
            "location": "Gunakan lokasi saya untuk mencari klinik berdekatan.",
        },
    },
}

# Which boxes must be ticked to use Lumis. The optional ones start unticked.
ITEMS = [("processing", True), ("adult", True), ("storage", False), ("location", False)]


def consent_document(lang: str, contact: str) -> dict:
    """The full consent screen for one language, with the contact filled in."""
    t = _TEXT[lang if lang in _TEXT else "en"]
    return {
        "version": CONSENT_VERSION,
        "language": lang if lang in _TEXT else "en",
        "title": t["title"],
        "sections": [{"heading": s["heading"], "body": s["body"].format(contact=contact)} for s in t["sections"]],
        "items": [{"id": i, "required": req, "label": t["items"][i]} for i, req in ITEMS],
    }


def text_fingerprint() -> str:
    """Changes whenever any consent wording changes (used by the test that enforces version bumps)."""
    import hashlib
    import json
    return hashlib.sha256(json.dumps(_TEXT, sort_keys=True, ensure_ascii=False).encode()).hexdigest()[:16]
