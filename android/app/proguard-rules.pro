# ProGuard / R8 rules — ezy_cable_digi (Magik Digi / Ezy Cable Digi)
#
# Intentionally EMPTY of keep rules.
#
# R8 already applies automatically:
#   1. Android's default rules (proguard-android-optimize.txt)
#   2. Each Flutter plugin's own bundled "consumer" rules (from its AAR)
#
# Do NOT add -keep rules speculatively: every kept class stays readable and
# weakens obfuscation. Add a rule ONLY when a minified release build proves
# it is needed (e.g. a crash naming a specific class) — and write down why.
#
# --- project-specific rules below this line (none required yet) ---
