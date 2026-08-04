local api = assert(WhisperTextProcessing, "WhisperTextProcessing is not loaded")
local process = assert(api.process, "WhisperTextProcessing.process is not loaded")
local validate = assert(
    api.validateRefinement,
    "WhisperTextProcessing.validateRefinement is not loaded"
)
local finalize = assert(
    api.finalizeRefinement,
    "WhisperTextProcessing.finalizeRefinement is not loaded"
)
local isVoiceCommand = assert(
    api.isVoiceCommand,
    "WhisperTextProcessing.isVoiceCommand is not loaded"
)

local acceptanceCases = {
    {
        name = "natural filler words and implicit room air",
        input = "blood pressure of 132 over 82 pulse 88, respiration is 20, oxygen saturation is 91% room air",
        expected = "BP 132/82 | P 88 | R 20 | SpO2 91% RA",
    },
    {
        name = "is and are fillers across vital fields",
        input = "blood pressure is 120 over 80 pulse is 70 respirations are 16 oxygen saturation is 98% on room air",
        expected = "BP 120/80 | P 70 | R 16 | SpO2 98% RA",
    },
    {
        name = "of fillers across vital fields",
        input = "blood pressure of 120 over 80 pulse of 70 respirations of 16 oxygen saturation of 98% on room air",
        expected = "BP 120/80 | P 70 | R 16 | SpO2 98% RA",
    },
    {
        name = "conjunction before oxygen field",
        input = "blood pressure 120 over 80 pulse 70 respirations 16 and oxygen saturation 98% on room air",
        expected = "BP 120/80 | P 70 | R 16 | SpO2 98% RA",
    },
    {
        name = "conjunction before end tidal field",
        input = "oxygen saturation 98% on room air and end tidal CO2 35",
        expected = "SpO2 98% RA | EtCO2 35 mm Hg",
    },
    {
        name = "full vital signs on non-rebreather",
        input = "blood pressure 140 over 95 pulse 89 respirations 20 oxygen saturation 98% on non-rebreather face mask",
        expected = "BP 140/95 | P 89 | R 20 | SpO2 98% NRFM",
    },
    {
        name = "full vital signs without oxygen modality",
        input = "blood pressure 120 over 80 pulse 70 respirations 16 oxygen saturation 98%",
        expected = "BP 120/80 | P 70 | R 16 | SpO2 98%",
    },
    {
        name = "supplemental oxygen and end tidal carbon dioxide",
        input = "blood pressure 132 over 82 pulse 88 respirations 20 oxygen saturation 98% on 2 liters per minute nasal cannula end tidal CO2 35",
        expected = "BP 132/82 | P 88 | R 20 | SpO2 98% 2 L/min NC | EtCO2 35 mm Hg",
    },
    {
        name = "standalone oxygen saturation on room air",
        input = "oxygen saturation 91% on room air",
        expected = "SpO2 91% RA",
    },
    {
        name = "standalone oxygen saturation without modality",
        input = "oxygen saturation 91%",
        expected = "SpO2 91%",
    },
    {
        name = "decimal oxygen saturation on room air",
        input = "oxygen saturation 98.5% on room air",
        expected = "SpO2 98.5% RA",
    },
    {
        name = "decimal-comma oxygen saturation without modality",
        input = "oxygen saturation 98,5%",
        expected = "SpO2 98,5%",
    },
    {
        name = "oxygen saturation range on room air",
        input = "oxygen saturation 95-98% on room air",
        expected = "SpO2 95-98% RA",
    },
    {
        name = "spaced oxygen saturation range on room air",
        input = "oxygen saturation 95 - 98% on room air",
        expected = "SpO2 95-98% RA",
    },
    {
        name = "spoken percent oxygen saturation on room air",
        input = "oxygen saturation 98 percent on room air",
        expected = "SpO2 98% RA",
    },
    {
        name = "spoken percent oxygen saturation with filler on room air",
        input = "oxygen saturation is 98 percent on room air",
        expected = "SpO2 98% RA",
    },
    {
        name = "abbreviated saturation with spoken percent and room air",
        input = "BP 120/80 P 70 R 16 SpO2 98 percent on room air",
        expected = "BP 120/80 | P 70 | R 16 | SpO2 98% RA",
    },
    {
        name = "partial vital signs do not append a dangling separator",
        input = "blood pressure 120 over 80 pulse 70 respirations 16. Condition stable.",
        expected = "BP 120/80 | P 70 | R 16. Condition stable.",
    },
    {
        name = "standalone room air reading preserves sentence period",
        input = "oxygen saturation 91% on room air. Condition improved.",
        expected = "SpO2 91% RA. Condition improved.",
    },
    {
        name = "standalone NRFM reading preserves sentence period",
        input = "oxygen saturation 98% on non-rebreather face mask. Condition improved.",
        expected = "SpO2 98% NRFM. Condition improved.",
    },
    {
        name = "standalone nasal cannula reading preserves sentence period",
        input = "oxygen saturation 96% on 2 liters per minute nasal cannula. Condition improved.",
        expected = "SpO2 96% 2 L/min NC. Condition improved.",
    },
    {
        name = "standalone end tidal carbon dioxide",
        input = "end tidal CO2 42",
        expected = "EtCO2 42 mm Hg",
    },
    {
        name = "decimal end tidal carbon dioxide",
        input = "EtCO2 35.5 mm Hg",
        expected = "EtCO2 35.5 mm Hg",
    },
    {
        name = "decimal-comma end tidal carbon dioxide",
        input = "EtCO2 35,5 mm Hg",
        expected = "EtCO2 35,5 mm Hg",
    },
    {
        name = "end tidal carbon dioxide range",
        input = "EtCO2 35-40 mm Hg",
        expected = "EtCO2 35-40 mm Hg",
    },
    {
        name = "spaced end tidal carbon dioxide range",
        input = "EtCO2 35 - 40 mm Hg",
        expected = "EtCO2 35-40 mm Hg",
    },
    {
        name = "dictated spaced end tidal carbon dioxide range",
        input = "end tidal CO2 35 - 40",
        expected = "EtCO2 35-40 mm Hg",
    },
    {
        name = "spoken end tidal carbon dioxide units",
        input = "end tidal CO2 35 millimeters of mercury",
        expected = "EtCO2 35 mm Hg",
    },
    {
        name = "spoken abbreviated end tidal carbon dioxide units",
        input = "EtCO2 35 millimeters mercury",
        expected = "EtCO2 35 mm Hg",
    },
    {
        name = "decimal EtCO2 follows respirations without SpO2",
        input = "blood pressure 120 over 80 pulse 70 respirations 16 end tidal CO2 35,5",
        expected = "BP 120/80 | P 70 | R 16 | EtCO2 35,5 mm Hg",
    },
    {
        name = "already abbreviated vital signs gain canonical separators",
        input = "BP 132/82 P 88 R 20 SpO2 98% RA EtCO2 35",
        expected = "BP 132/82 | P 88 | R 20 | SpO2 98% RA | EtCO2 35 mm Hg",
    },
    {
        name = "abbreviated saturation without percent preserves sentence punctuation",
        input = "BP 120/80 P 70 R 16 SpO2 98. Condition stable.",
        expected = "BP 120/80 | P 70 | R 16 | SpO2 98%. Condition stable.",
    },
    {
        name = "abbreviated saturation with spoken room air",
        input = "BP 120/80 P 70 R 16 SpO2 98% on room air",
        expected = "BP 120/80 | P 70 | R 16 | SpO2 98% RA",
    },
    {
        name = "abbreviated saturation with spoken non-rebreather",
        input = "BP 120/80 P 70 R 16 SpO2 98% on non-rebreather face mask",
        expected = "BP 120/80 | P 70 | R 16 | SpO2 98% NRFM",
    },
    {
        name = "abbreviated saturation with spoken nasal cannula flow",
        input = "BP 120/80 P 70 R 16 SpO2 98% on 2 liters per minute nasal cannula",
        expected = "BP 120/80 | P 70 | R 16 | SpO2 98% 2 L/min NC",
    },
    {
        name = "abbreviated saturation with spoken nasal cannula",
        input = "BP 120/80 P 70 R 16 SpO2 98% on nasal cannula",
        expected = "BP 120/80 | P 70 | R 16 | SpO2 98% NC",
    },
    {
        name = "EtCO2 in ordinary prose does not gain a vital separator",
        input = "The EtCO2 35 mm Hg was recorded.",
        expected = "The EtCO2 35 mm Hg was recorded.",
    },
    {
        name = "separated SpO2 and EtCO2 prose does not gain a vital separator",
        input = "The SpO2 98% improved after oxygen, and EtCO2 35 mm Hg was recorded.",
        expected = "The SpO2 98% improved after oxygen, and EtCO2 35 mm Hg was recorded.",
    },
    {
        name = "SpO2 and later EtCO2 sentences remain prose",
        input = "SpO2 98% on room air. Later, EtCO2 35 mm Hg was recorded.",
        expected = "SpO2 98% on room air. Later, EtCO2 35 mm Hg was recorded.",
    },
    {
        name = "spoken punctuation between vital fields",
        input = "blood pressure 140 over 95 punctuation comma pulse 89 punctuation comma respirations 20 punctuation full stop oxygen saturation 98% on non-rebreather face mask",
        expected = "BP 140/95 | P 89 | R 20 | SpO2 98% NRFM",
    },
    {
        name = "ordinary period noun is preserved",
        input = "The patient had a prolonged period of apnea.",
        expected = "The patient had a prolonged period of apnea.",
    },
    {
        name = "punctuation command is not matched inside a word",
        input = "This is a colonoscopy.",
        expected = "This is a colonoscopy.",
    },
    {
        name = "explicit punctuation colon command works",
        input = "Findings punctuation colon normal.",
        expected = "Findings: normal.",
    },
    {
        name = "anatomical colon noun is preserved",
        input = "The colon was normal.",
        expected = "The colon was normal.",
    },
    {
        name = "clock time and missing sentence space",
        input = "The ETA is 15: 45.The ETA is 1545.",
        expected = "The ETA is 15:45. The ETA is 1545.",
    },
    {
        name = "medication dose receives a leading zero",
        input = "Administer .5 mg naloxone.",
        expected = "Administer 0.5 mg naloxone.",
    },
    {
        name = "signed decimal receives a leading zero",
        input = "The change was -.5 mg.",
        expected = "The change was -0.5 mg.",
    },
    {
        name = "existing leading zero is preserved",
        input = "Administer 0.5 mg naloxone.",
        expected = "Administer 0.5 mg naloxone.",
    },
    {
        name = "dotted clinical initialism is preserved",
        input = "The E.K.G. showed ST elevation.",
        expected = "The E.K.G. showed ST elevation.",
    },
    {
        name = "dotted geographic initialism is preserved",
        input = "The U.S. exam standard was used.",
        expected = "The U.S. exam standard was used.",
    },
    {
        name = "missing sentence space after dotted initialism is repaired",
        input = "The E.K.G. was obtained.The tracing was abnormal.",
        expected = "The E.K.G. was obtained. The tracing was abnormal.",
    },
    {
        name = "mixed-case term preserved at sentence boundary",
        input = "Acidosis noted. pH was 7.20.",
        expected = "Acidosis noted. pH was 7.20.",
    },
    {
        name = "mixed-case unit preserved at paragraph boundary",
        input = "mL was documented.\nmL remained unchanged.",
        expected = "mL was documented.\nmL remained unchanged.",
    },
    {
        name = "leading paragraph command",
        input = "Format new paragraph, blood pressure 120 over 70 pulse 75 respirations 16 oxygen saturation 99% on room air",
        expected = "\n\nBP 120/70 | P 75 | R 16 | SpO2 99% RA",
    },
    {
        name = "ordinary new line phrase is preserved",
        input = "A new line was placed for norepinephrine.",
        expected = "A new line was placed for norepinephrine.",
    },
    {
        name = "non-numeric vital-sign prose is preserved",
        input = "The blood pressure of the patient was unobtainable. Respiration is labored.",
        expected = "The blood pressure of the patient was unobtainable. Respiration is labored.",
    },
    {
        name = "unrelated clinical prose remains unchanged",
        input = "The patient was resting comfortably on room air.",
        expected = "The patient was resting comfortably on room air.",
    },
}

for _, case in ipairs(acceptanceCases) do
    local actual = process(case.input)
    assert(actual == case.expected, string.format(
        "%s failed\nexpected: %q\nactual:   %q",
        case.name,
        case.expected,
        actual
    ))
end

local acceptedRefinements = {
    {
        name = "punctuation and capitalization",
        source = "the patient denies chest pain and reports nausea",
        candidate = "The patient denies chest pain, and reports nausea.",
    },
    {
        name = "allowed filler removal",
        source = "Um, you know, the patient is alert and oriented.",
        candidate = "The patient is alert and oriented.",
    },
    {
        name = "spoken punctuation canonicalizes identically",
        source = "Findings punctuation colon normal punctuation full stop Next sentence",
        candidate = "Findings: normal. Next sentence",
    },
    {
        name = "canonical vital signs preserved",
        source = "BP 132/82 | P 88 | R 20 | SpO2 98% 2 L/min NC | EtCO2 35 mm Hg",
        candidate = "BP 132/82 | P 88 | R 20 | SpO2 98% 2 L/min NC | EtCO2 35 mm Hg",
    },
    {
        name = "unchanged non-ASCII text accepts punctuation",
        source = "The name is José",
        candidate = "The name is José.",
    },
    {
        name = "comma-delimited I mean remains an allowed filler",
        source = "I mean, the finding is unchanged.",
        candidate = "The finding is unchanged.",
    },
    {
        name = "ordinary short word may gain sentence capitalization",
        source = "he remained alert.",
        candidate = "He remained alert.",
    },
}

for _, case in ipairs(acceptedRefinements) do
    local ok, reason = validate(case.source, case.candidate)
    assert(ok, case.name .. " should be accepted: " .. tostring(reason))
end

local rejectedRefinements = {
    {
        name = "changed number",
        source = "BP 132/82 | P 88 | R 20 | SpO2 91% RA",
        candidate = "BP 132/82 | P 89 | R 20 | SpO2 91% RA",
        reason = "numeric facts changed",
    },
    {
        name = "removed percentage marker",
        source = "SpO2 91% RA",
        candidate = "SpO2 91 RA",
        reason = "percentage markers changed",
    },
    {
        name = "removed negation",
        source = "The patient denies chest pain.",
        candidate = "The patient has chest pain.",
        reason = "meaningful words changed or reordered",
    },
    {
        name = "added clinical claim",
        source = "The patient reports nausea.",
        candidate = "The patient reports severe nausea.",
        reason = "meaningful words changed or reordered",
    },
    {
        name = "changed medication unit",
        source = "Administered 2 mg naloxone.",
        candidate = "Administered 2 mcg naloxone.",
        reason = "meaningful words changed or reordered",
    },
    {
        name = "reordered facts",
        source = "Pulse 88 and respirations 20.",
        candidate = "Respirations 20 and pulse 88.",
        reason = "numeric facts changed",
    },
    {
        name = "empty response",
        source = "The patient is alert.",
        candidate = "   ",
        reason = "empty response",
    },
    {
        name = "observed model sentence deletion",
        source = "Ok, here is my itemized list. Let's test whether it worked. First item is great.",
        candidate = "Let's test whether it worked. First item is great.",
        reason = "meaningful words changed or reordered",
    },
    {
        name = "inequality direction changed",
        source = "Glucose < 50 mg/dL.",
        candidate = "Glucose > 50 mg/dL.",
        reason = "protected symbols changed",
    },
    {
        name = "unicode inequality direction changed",
        source = "Temperature ≤ 38 C.",
        candidate = "Temperature ≥ 38 C.",
        reason = "protected symbols changed",
    },
    {
        name = "ratio separator changed",
        source = "Ratio 1/2.",
        candidate = "Ratio 1:2.",
        reason = "protected symbols changed",
    },
    {
        name = "range changed to fraction",
        source = "Dose 1–2 mg.",
        candidate = "Dose 1/2 mg.",
        reason = "protected symbols changed",
    },
    {
        name = "inequality moved to another measurement",
        source = "Glucose < 50 and pulse 60.",
        candidate = "Glucose 50 and pulse < 60.",
        reason = "protected symbols changed",
    },
    {
        name = "percentage marker moved to another measurement",
        source = "SpO2 98 and ejection fraction 50%.",
        candidate = "SpO2 98% and ejection fraction 50.",
        reason = "protected symbols changed",
    },
    {
        name = "non-ASCII name changed",
        source = "The name is José.",
        candidate = "The name is Josè.",
        reason = "non-ASCII text changed",
    },
    {
        name = "meaningful you know phrase removed",
        source = "Do you know whether the medication was taken?",
        candidate = "Do whether the medication was taken?",
        reason = "meaningful words changed or reordered",
    },
    {
        name = "case-sensitive abbreviation changed",
        source = "Send the patient to US for further imaging.",
        candidate = "Send the patient to us for further imaging.",
        reason = "case-sensitive terms changed",
    },
    {
        name = "case-sensitive abbreviation moved between repeated words",
        source = "The US exam was discussed with us.",
        candidate = "The us exam was discussed with US.",
        reason = "case-sensitive terms changed",
    },
    {
        name = "target app context preserves title-case abbreviation",
        source = "Na was 135 mmol/L.",
        candidate = "na was 135 mmol/L.",
        appBundleID = "com.apple.Terminal",
        reason = "case-sensitive terms changed",
    },
    {
        name = "internal-uppercase clinical terms changed",
        source = "The arterial pH was measured after 2 mL.",
        candidate = "The arterial ph was measured after 2 ml.",
        reason = "case-sensitive terms changed",
    },
    {
        name = "single-letter clinical abbreviation changed",
        source = "The blood type is O positive.",
        candidate = "The blood type is o positive.",
        reason = "case-sensitive terms changed",
    },
    {
        name = "title-case clinical abbreviations changed",
        source = "The Na, Ca, Cl, Mg, Fe, and Hb were measured.",
        candidate = "The na, ca, cl, mg, fe, and hb were measured.",
        reason = "case-sensitive terms changed",
    },
    {
        name = "leading-decimal dose changed tenfold",
        source = "Administer .5 mg naloxone.",
        candidate = "Administer 5 mg naloxone.",
        reason = "numeric facts changed",
    },
    {
        name = "signed leading-decimal dose changed",
        source = "The offset was -.5 units.",
        candidate = "The offset was -5 units.",
        reason = "numeric facts changed",
    },
    {
        name = "accent moved between repeated stems",
        source = "José treated Jos.",
        candidate = "Jos treated José.",
        reason = "meaningful words changed or reordered",
    },
    {
        name = "decimal comma changed tenfold",
        source = "Administer 1,5 mg naloxone.",
        candidate = "Administer 15 mg naloxone.",
        reason = "numeric facts changed",
    },
    {
        name = "leading decimal comma changed tenfold",
        source = "Administer ,5 mg naloxone.",
        candidate = "Administer 5 mg naloxone.",
        reason = "numeric facts changed",
    },
    {
        name = "signed leading decimal comma changed",
        source = "The offset was -,5 units.",
        candidate = "The offset was -5 units.",
        reason = "numeric facts changed",
    },
    {
        name = "dose moved between medications",
        source = "Give naloxone 2 mg and epinephrine 1 mg.",
        candidate = "Give naloxone mg and epinephrine 2 mg 1.",
        reason = "numeric facts changed",
    },
    {
        name = "dose unit slash moved between words",
        source = "Give 5 mg/kg naloxone.",
        candidate = "Give 5 mg kg/naloxone.",
        reason = "protected symbols changed",
    },
    {
        name = "clinical abbreviation ampersands removed",
        source = "Record H&H and D&C history.",
        candidate = "Record H H and D C history.",
        reason = "protected symbols changed",
    },
    {
        name = "time colon moved after adjacent number",
        source = "At 12:30 administer 5 mg.",
        candidate = "At 12 30: administer 5 mg.",
        reason = "protected symbols changed",
    },
}

for _, case in ipairs(rejectedRefinements) do
    local ok, reason = validate(case.source, case.candidate, case.appBundleID)
    assert(not ok, case.name .. " should be rejected")
    assert(reason == case.reason, string.format(
        "%s returned wrong reason: expected %q, got %q",
        case.name,
        case.reason,
        reason
    ))
end

local baseline = "blood pressure 132 over 82 pulse 88 respirations 20 oxygen saturation 91% on room air"
local unsafeCandidate = "BP 132/82 | P 89 | R 20 | SpO2 91% RA"
local fallback, accepted, reason = finalize(baseline, unsafeCandidate)
assert(not accepted and reason == "numeric facts changed")
assert(fallback == "BP 132/82 | P 88 | R 20 | SpO2 91% RA")

local safeCandidate = "BP 132/82 | P 88 | R 20 | SpO2 91% RA"
local final, safeAccepted = finalize(baseline, safeCandidate)
assert(safeAccepted)
assert(final == safeCandidate)

assert(isVoiceCommand("Voice command open calendar"))
assert(isVoiceCommand("please run voice command paste template"))
assert(not isVoiceCommand("The voicemail command failed."))
assert(not isVoiceCommand("Routine clinical dictation."))

for systolic = 90, 220, 10 do
    local diastolic = math.floor(systolic * 0.6)
    local pulse = systolic - 20
    local respirations = math.floor(systolic / 10)
    local saturation = 88 + (systolic % 13)
    local input = string.format(
        "blood pressure %d over %d pulse %d respirations %d oxygen saturation %d%% on room air",
        systolic,
        diastolic,
        pulse,
        respirations,
        saturation
    )
    local expected = string.format(
        "BP %d/%d | P %d | R %d | SpO2 %d%% RA",
        systolic,
        diastolic,
        pulse,
        respirations,
        saturation
    )
    assert(process(input) == expected, "generated vital-sign case failed")
end

local twoSetInput =
    "blood pressure 120 over 80 pulse 70 respirations 16 oxygen saturation 95% on room air. " ..
    "blood pressure 130 over 85 pulse 75 respirations 18 oxygen saturation 98% on non-rebreather face mask"
local twoSetExpected =
    "BP 120/80 | P 70 | R 16 | SpO2 95% RA. " ..
    "BP 130/85 | P 75 | R 18 | SpO2 98% NRFM"
assert(process(twoSetInput) == twoSetExpected, "multiple vital-sign sets were not all formatted")
assert(process(twoSetExpected) == twoSetExpected, "multiple formatted vital-sign sets are not idempotent")

for _, case in ipairs(acceptanceCases) do
    local once = process(case.input)
    local repeated = once
    for _ = 1, 100 do repeated = process(repeated) end
    assert(repeated == once, case.name .. " is not idempotent")
end

print(string.format(
    "PASS: %d acceptance, %d accepted refinement, %d rejected refinement, generated cases, 100x idempotence",
    #acceptanceCases,
    #acceptedRefinements,
    #rejectedRefinements
))
