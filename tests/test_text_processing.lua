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
        name = "full vital signs on non-rebreather",
        input = "blood pressure 140 over 95 pulse 89 respirations 20 oxygen saturation 98% on non-rebreather face mask",
        expected = "BP 140/95 | P 89 | R 20 | SpO2 98% NRFM",
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
        name = "standalone end tidal carbon dioxide",
        input = "end tidal CO2 42",
        expected = "EtCO2 42 mm Hg",
    },
    {
        name = "already abbreviated vital signs gain canonical separators",
        input = "BP 132/82 P 88 R 20 SpO2 98% RA EtCO2 35",
        expected = "BP 132/82 | P 88 | R 20 | SpO2 98% RA | EtCO2 35 mm Hg",
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
        input = "blood pressure 140 over 95 comma pulse 89 comma respirations 20 period oxygen saturation 98% on non-rebreather face mask",
        expected = "BP 140/95 | P 89 | R 20 | SpO2 98% NRFM",
    },
    {
        name = "punctuation command is not matched inside a word",
        input = "This is a colonoscopy.",
        expected = "This is a colonoscopy.",
    },
    {
        name = "standalone colon command still works",
        input = "Findings colon normal.",
        expected = "Findings: normal.",
    },
    {
        name = "clock time and missing sentence space",
        input = "The ETA is 15: 45.The ETA is 1545.",
        expected = "The ETA is 15:45. The ETA is 1545.",
    },
    {
        name = "leading paragraph command",
        input = "New paragraph, blood pressure 120 over 70 pulse 75 respirations 16 oxygen saturation 99% on room air",
        expected = "\n\nBP 120/70 | P 75 | R 16 | SpO2 99% RA",
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
        source = "Findings colon normal period Next sentence",
        candidate = "Findings: normal. Next sentence",
    },
    {
        name = "canonical vital signs preserved",
        source = "BP 132/82 | P 88 | R 20 | SpO2 98% 2 L/min NC | EtCO2 35 mm Hg",
        candidate = "BP 132/82 | P 88 | R 20 | SpO2 98% 2 L/min NC | EtCO2 35 mm Hg",
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
}

for _, case in ipairs(rejectedRefinements) do
    local ok, reason = validate(case.source, case.candidate)
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
