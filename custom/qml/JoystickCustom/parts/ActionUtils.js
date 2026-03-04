.pragma library

function normTitle(s) {
    return String(s || "").replace(/&/g, "").trim().toLowerCase();
}

function assignableActionAtComboIndex(activeJoystick, ci) {
    if (!activeJoystick || !activeJoystick.assignableActions) return null;
    var n = activeJoystick.assignableActions.count;
    if (ci < 0 || ci >= n) return null;
    return activeJoystick.assignableActions.get(ci);
}
