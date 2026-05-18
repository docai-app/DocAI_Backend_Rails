#!/usr/bin/env python3
import argparse
import json
import os
import sys
import time

import azure.cognitiveservices.speech as speechsdk


def weighted_average(values):
    weighted_sum = 0.0
    total_weight = 0.0
    for value, weight in values:
        if value is None:
            continue
        weighted_sum += float(value) * float(weight or 1)
        total_weight += float(weight or 1)
    if total_weight == 0:
        return None
    return round(weighted_sum / total_weight, 2)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--audio", required=True)
    parser.add_argument("--reference", required=True)
    parser.add_argument("--locale", default=os.environ.get("AZURE_SPEECH_LOCALE", "en-US"))
    args = parser.parse_args()

    speech_key = os.environ["AZURE_SPEECH_KEY"]
    speech_region = os.environ["AZURE_SPEECH_REGION"]

    with open(args.reference, "r", encoding="utf-8") as file:
        reference_text = file.read().strip()

    speech_config = speechsdk.SpeechConfig(subscription=speech_key, region=speech_region)
    speech_config.speech_recognition_language = args.locale
    audio_config = speechsdk.AudioConfig(filename=args.audio)

    assessment_config = speechsdk.PronunciationAssessmentConfig(
        reference_text=reference_text,
        grading_system=speechsdk.PronunciationAssessmentGradingSystem.HundredMark,
        granularity=speechsdk.PronunciationAssessmentGranularity.Word,
        enable_miscue=False,
    )
    assessment_config.enable_prosody_assessment()

    recognizer = speechsdk.SpeechRecognizer(speech_config=speech_config, audio_config=audio_config)
    assessment_config.apply_to(recognizer)

    done = False
    segment_results = []

    def recognized(evt):
        if evt.result.reason != speechsdk.ResultReason.RecognizedSpeech:
            return
        payload = json.loads(evt.result.properties.get(
            speechsdk.PropertyId.SpeechServiceResponse_JsonResult
        ))
        segment_results.append(payload)

    def stop(_evt):
        nonlocal done
        done = True

    recognizer.recognized.connect(recognized)
    recognizer.session_stopped.connect(stop)
    recognizer.canceled.connect(stop)

    recognizer.start_continuous_recognition()
    deadline = time.time() + int(os.environ.get("AZURE_SPEECH_TIMEOUT_SECONDS", "180"))
    while not done and time.time() < deadline:
        time.sleep(0.2)
    recognizer.stop_continuous_recognition()

    if not segment_results:
        raise RuntimeError("Azure continuous pronunciation returned no recognized segments.")

    accuracy_values = []
    fluency_values = []
    completeness_values = []
    prosody_values = []
    pron_values = []
    all_words = []
    display_texts = []

    for segment in segment_results:
        display_texts.append(segment.get("DisplayText", ""))
        nbest = (segment.get("NBest") or [{}])[0]
        assessment = nbest.get("PronunciationAssessment") or {}
        words = nbest.get("Words") or []
        weight = max(len(words), 1)

        accuracy_values.append((assessment.get("AccuracyScore"), weight))
        fluency_values.append((assessment.get("FluencyScore"), weight))
        completeness_values.append((assessment.get("CompletenessScore"), weight))
        prosody_values.append((assessment.get("ProsodyScore"), weight))
        pron_values.append((assessment.get("PronScore"), weight))
        all_words.extend(words)

    aggregated_assessment = {
        "AccuracyScore": weighted_average(accuracy_values),
        "FluencyScore": weighted_average(fluency_values),
        "CompletenessScore": weighted_average(completeness_values),
        "ProsodyScore": weighted_average(prosody_values),
        "PronScore": weighted_average(pron_values),
    }

    display_text = " ".join([text for text in display_texts if text]).strip()
    output = {
        "provider_name": "azure_speech",
        "mode": "continuous_sdk",
        "reference_text_used": reference_text,
        "segment_count": len(segment_results),
        "aggregated_result": {
            "DisplayText": display_text,
            "PronunciationAssessment": aggregated_assessment,
            "NBest": [
                {
                    "Display": display_text,
                    "PronunciationAssessment": aggregated_assessment,
                    "Words": all_words,
                }
            ],
        },
        "segment_results": segment_results,
    }

    print(json.dumps(output, ensure_ascii=False))


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        print(str(exc), file=sys.stderr)
        sys.exit(1)
