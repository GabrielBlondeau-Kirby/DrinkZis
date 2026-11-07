-- DrinkZis : un « sac » à potions flottant, rangé par catégorie.
-- Une icône ronde ouvre / ferme le sac (même en combat, via un handler sécurisé).
local ADDON = ...
local PREFIX = "|cff66ccffDrinkZis|r : "
local ICON = "Interface\\Icons\\INV_Potion_51"

---------------------------------------------------------------------------
-- Compatibilité API
---------------------------------------------------------------------------
local GetNumSlots = (C_Container and C_Container.GetContainerNumSlots) or GetContainerNumSlots
local GetItemID   = (C_Container and C_Container.GetContainerItemID) or GetContainerItemID
local GetItemCooldownCompat = (C_Container and C_Container.GetItemCooldown) or GetItemCooldown
local GetItemSpellCompat = (C_Item and C_Item.GetItemSpell) or GetItemSpell
local GetItemInfoCompat  = (C_Item and C_Item.GetItemInfo) or GetItemInfo
local GetItemIconCompat  = (C_Item and C_Item.GetItemIconByID) or GetItemIcon
local GetItemCountCompat = (C_Item and C_Item.GetItemCount) or GetItemCount
local BACKDROP_TEMPLATE  = BackdropTemplateMixin and "BackdropTemplate" or nil

local function SpellName(id)
    if C_Spell and C_Spell.GetSpellName then return C_Spell.GetSpellName(id) end
    return (GetSpellInfo(id))
end

---------------------------------------------------------------------------
-- Catégories et thèmes
---------------------------------------------------------------------------
local CATEGORIES = {
    { key = "heal",   label = "Vie",    color = { 0.95, 0.25, 0.25 } },
    { key = "mana",   label = "Mana",   color = { 0.30, 0.55, 1.00 } },
    { key = "combat", label = "Combat", color = { 1.00, 0.60, 0.10 } },
    { key = "buff",   label = "Buffs",  color = { 0.70, 0.40, 1.00 } },
}
local CAT_BY_KEY = {}
for _, c in ipairs(CATEGORIES) do CAT_BY_KEY[c.key] = c end

local THEMES = {
    { key = "dark",   label = "Sombre",    bg = { 0, 0, 0, 0.80 },          border = { 0.55, 0.55, 0.55 } },
    { key = "gold",   label = "Doré",      bg = { 0.10, 0.07, 0.03, 0.88 }, border = { 1.00, 0.80, 0.20 } },
    { key = "arcane", label = "Arcane",    bg = { 0.05, 0.03, 0.15, 0.88 }, border = { 0.65, 0.45, 1.00 } },
    { key = "fel",    label = "Gangrène",  bg = { 0.02, 0.10, 0.02, 0.88 }, border = { 0.35, 1.00, 0.20 } },
    { key = "blood",  label = "Sang",      bg = { 0.12, 0.02, 0.02, 0.88 }, border = { 0.90, 0.15, 0.15 } },
}
local THEME_BY_KEY = {}
for _, t in ipairs(THEMES) do THEME_BY_KEY[t.key] = t end

local DB
local function InitDB()
    DrinkZisDB = DrinkZisDB or {}
    DB = DrinkZisDB
    if DB.auto == nil then DB.auto = true end
    DB.theme = THEME_BY_KEY[DB.theme or ""] and DB.theme or "dark"
    DB.hide = DB.hide or {}
end

---------------------------------------------------------------------------
-- Classement des objets
---------------------------------------------------------------------------
local FOOD, DRINK = SpellName(433), SpellName(430)

local scan = CreateFrame("GameTooltip", "DrinkZisScanTip", nil, "GameTooltipTemplate")

-- Ligne « Utiliser : … » de la description, en minuscules ; nil si pas en cache.
local function UseLine(itemID)
    scan:SetOwner(WorldFrame, "ANCHOR_NONE")
    scan:ClearLines()
    scan:SetHyperlink("item:" .. itemID)
    local n = scan:NumLines()
    if n == 0 then return nil end
    for i = 2, n do
        local fs = _G["DrinkZisScanTipTextLeft" .. i]
        local text = fs and fs:GetText()
        if text then
            text = text:lower()
            if text:find("^utiliser") or text:find("^use:") then return text end
        end
    end
    return ""
end

local function Has(s, words)
    for _, w in ipairs(words) do
        if s:find(w, 1, true) then return true end
    end
    return false
end

local cache = {} -- itemID -> clé de catégorie, ou false
-- Renvoie la catégorie, false si ce n'est pas une potion, nil si pas encore chargé.
local function Classify(itemID)
    if cache[itemID] ~= nil then return cache[itemID] end
    local name, _, _, _, _, _, _, _, _, _, _, classID = GetItemInfoCompat(itemID)
    if not name then return nil end
    local result = false
    local spell = GetItemSpellCompat(itemID)
    if classID == 0 and spell and spell ~= FOOD and spell ~= DRINK then
        local use = UseLine(itemID)
        if use == nil then return nil end
        local n = name:lower()
        local health = Has(use, { "points de vie", "health" })
        local mana   = Has(use, { "points de mana", "mana" })
        if Has(n, { "bandage" }) then
            result = false
        elseif Has(n, { "élixir", "elixir", "flacon", "flask", "parchemin", "scroll" }) then
            result = "buff"
        elseif Has(n, { "potion", "pierre de soins", "healthstone", "mana" }) then
            if health then
                result = "heal"
            elseif mana then
                result = "mana"
            elseif Has(n, { "potion" }) then
                result = "combat"
            end
        end
    end
    cache[itemID] = result
    return result
end

-- { heal = { id, id, … }, mana = { … }, … } : un objet par type, pas par pile.
local function CollectItems()
    local byCat, seen, missing = {}, {}, false
    for bag = 0, 4 do
        for slot = 1, (GetNumSlots(bag) or 0) do
            local id = GetItemID(bag, slot)
            if id and not seen[id] then
                local cat = Classify(id)
                if cat == nil then missing = true end
                if cat then
                    seen[id] = true
                    byCat[cat] = byCat[cat] or {}
                    table.insert(byCat[cat], id)
                end
            end
        end
    end
    for _, list in pairs(byCat) do
        table.sort(list, function(a, b) return (GetItemInfoCompat(a) or "") < (GetItemInfoCompat(b) or "") end)
    end
    return byCat, missing
end

---------------------------------------------------------------------------
-- Icône ronde (ouvre / ferme le sac, aussi en combat)
---------------------------------------------------------------------------
local TOGGLE = 52
local k = TOGGLE / 31 -- mise à l'échelle du modèle « bouton de minimap »

local toggle = CreateFrame("Button", "DrinkZisToggle", UIParent, "SecureHandlerClickTemplate")
toggle:SetSize(TOGGLE, TOGGLE)
toggle:SetFrameStrata("MEDIUM")
toggle:SetFrameLevel(20)
toggle:SetMovable(true)
toggle:SetClampedToScreen(true)
toggle:RegisterForClicks("AnyUp")
toggle:RegisterForDrag("LeftButton")

local tIcon = toggle:CreateTexture(nil, "ARTWORK")
tIcon:SetTexture(ICON)
tIcon:SetSize(20 * k, 20 * k)
tIcon:SetPoint("TOPLEFT", 6 * k, -5.5 * k)
if tIcon.SetMask then tIcon:SetMask("Interface\\CharacterFrame\\TempPortraitAlphaMask") end

local tRing = toggle:CreateTexture(nil, "OVERLAY")
tRing:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
tRing:SetSize(53 * k, 53 * k)
tRing:SetPoint("TOPLEFT")

local tHl = toggle:CreateTexture(nil, "HIGHLIGHT")
tHl:SetTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
tHl:SetBlendMode("ADD")
tHl:SetAllPoints(tIcon)

---------------------------------------------------------------------------
-- Le sac
---------------------------------------------------------------------------
local bagTemplate = "SecureHandlerStateTemplate" .. (BACKDROP_TEMPLATE and "," .. BACKDROP_TEMPLATE or "")
local bag = CreateFrame("Frame", "DrinkZisBag", UIParent, bagTemplate)
bag:SetFrameStrata("MEDIUM")
bag:SetFrameLevel(5)
bag:SetPoint("TOPLEFT", toggle, "CENTER", 0, 2)
bag:SetSize(200, 60)
bag:Hide()

local emptyText = bag:CreateFontString(nil, "OVERLAY", "GameFontDisable")
emptyText:SetText("Aucune potion")

toggle:SetFrameRef("bag", bag)
toggle:SetAttribute("_onclick", [[
    local bag = self:GetFrameRef("bag")
    bag:SetAttribute("autoopened", nil)
    if bag:IsShown() then bag:Hide() else bag:Show() end
]])

-- Ouverture auto en combat / fermeture à la sortie (seulement si c'est l'auto qui a ouvert).
bag:SetAttribute("_onstate-combat", [[
    if not self:GetAttribute("auto") then return end
    if newstate == "1" then
        if not self:IsShown() then
            self:SetAttribute("autoopened", 1)
            self:Show()
        end
    elseif self:GetAttribute("autoopened") then
        self:Hide()
        self:SetAttribute("autoopened", nil)
    end
]])
RegisterStateDriver(bag, "combat", "[combat] 1; 0")

-- On ne mémorise que les ouvertures / fermetures manuelles.
bag:HookScript("OnShow", function(self) if DB and not self:GetAttribute("autoopened") then DB.open = true end end)
bag:HookScript("OnHide", function(self) if DB and not self:GetAttribute("autoopened") then DB.open = false end end)

local function ApplyTheme()
    local t = THEME_BY_KEY[DB.theme]
    if bag.SetBackdrop then
        bag:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 14,
            insets = { left = 3, right = 3, top = 3, bottom = 3 },
        })
        bag:SetBackdropColor(unpack(t.bg))
        bag:SetBackdropBorderColor(unpack(t.border))
    end
    tRing:SetVertexColor(unpack(t.border))
end

---------------------------------------------------------------------------
-- Emplacements (boutons sécurisés, créés / placés hors combat uniquement)
---------------------------------------------------------------------------
local SLOT, GAP, COLS, LABEL_W = 34, 4, 6, 52
local slots, labels = {}, {}

local function UpdateSlot(b)
    local count = GetItemCountCompat(b.itemID) or 0
    b.count:SetText(count > 1 and count or "")
    b.icon:SetDesaturated(count == 0)
    local start, duration, enable = GetItemCooldownCompat(b.itemID)
    if CooldownFrame_Set then
        CooldownFrame_Set(b.cd, start, duration, enable)
    elseif start and duration and duration > 0 then
        b.cd:SetCooldown(start, duration)
    end
end

local function GetSlot(i)
    local b = slots[i]
    if b then return b end
    b = CreateFrame("Button", "DrinkZisSlot" .. i, bag, "SecureActionButtonTemplate")
    b:SetSize(SLOT, SLOT)
    b:RegisterForClicks("AnyUp", "AnyDown")
    b:SetAttribute("type", "item")

    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetAllPoints()
    b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    b.border = b:CreateTexture(nil, "OVERLAY")
    b.border:SetTexture("Interface\\Buttons\\UI-Quickslot2")
    b.border:SetPoint("CENTER")
    b.border:SetSize(SLOT * 1.65, SLOT * 1.65)

    b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    b:SetPushedTexture("Interface\\Buttons\\UI-Quickslot-Depress")

    b.cd = CreateFrame("Cooldown", nil, b, "CooldownFrameTemplate")
    b.cd:SetAllPoints()

    b.count = b:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    b.count:SetPoint("BOTTOMRIGHT", -2, 2)

    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetHyperlink("item:" .. self.itemID)
        local c = CAT_BY_KEY[self.cat]
        GameTooltip:AddLine("DrinkZis — " .. c.label, c.color[1], c.color[2], c.color[3])
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)

    slots[i] = b
    return b
end

local function GetLabel(i)
    local l = labels[i]
    if not l then
        l = bag:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        l:SetJustifyH("LEFT")
        l:SetWidth(LABEL_W - 4)
        labels[i] = l
    end
    return l
end

local pendingRebuild = false

local function Rebuild()
    if not DB then return end
    if InCombatLockdown() then pendingRebuild = true return end
    pendingRebuild = false

    local byCat = CollectItems()
    local x0 = TOGGLE / 2 + 10 -- dégage l'icône ronde qui chevauche le coin
    local y, nSlot, nLabel, maxCols = -10, 0, 0, 0

    for _, c in ipairs(CATEGORIES) do
        local list = byCat[c.key]
        if list and not DB.hide[c.key] then
            nLabel = nLabel + 1
            local l = GetLabel(nLabel)
            l:SetText(c.label)
            l:SetTextColor(unpack(c.color))
            l:ClearAllPoints()
            l:SetPoint("LEFT", bag, "TOPLEFT", x0, y - SLOT / 2)
            l:Show()
            for i, id in ipairs(list) do
                nSlot = nSlot + 1
                local b = GetSlot(nSlot)
                local col, row = (i - 1) % COLS, math.floor((i - 1) / COLS)
                b.itemID, b.cat = id, c.key
                b:SetAttribute("item", "item:" .. id)
                b.icon:SetTexture(GetItemIconCompat(id))
                b.border:SetVertexColor(unpack(c.color))
                b:ClearAllPoints()
                b:SetPoint("TOPLEFT", bag, "TOPLEFT", x0 + LABEL_W + col * (SLOT + GAP), y - row * (SLOT + GAP))
                b:Show()
                UpdateSlot(b)
                maxCols = math.max(maxCols, col + 1)
            end
            y = y - (math.floor((#list - 1) / COLS) + 1) * (SLOT + GAP) - 4
        end
    end

    for i = nSlot + 1, #slots do slots[i]:Hide(); slots[i].itemID = nil end
    for i = nLabel + 1, #labels do labels[i]:Hide() end

    if nSlot == 0 then
        emptyText:ClearAllPoints()
        emptyText:SetPoint("LEFT", bag, "TOPLEFT", x0, -24)
        emptyText:Show()
        bag:SetSize(x0 + 110, 48)
    else
        emptyText:Hide()
        bag:SetSize(x0 + LABEL_W + maxCols * (SLOT + GAP) + 6, math.max(-y + 6, TOGGLE / 2 + 12))
    end
end

local function UpdateAllSlots()
    for _, b in ipairs(slots) do
        if b:IsShown() and b.itemID then UpdateSlot(b) end
    end
end

---------------------------------------------------------------------------
-- Déplacement et position
---------------------------------------------------------------------------
toggle:SetScript("OnDragStart", function(self)
    if IsShiftKeyDown() and not InCombatLockdown() and not DB.locked then self:StartMoving() end
end)
toggle:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local point, _, relPoint, x, y = self:GetPoint()
    DB.pos = { point, relPoint, x, y }
end)
toggle:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText("DrinkZis", 0.4, 0.8, 1)
    GameTooltip:AddLine("Clic : ouvrir / fermer le sac", 1, 1, 1)
    GameTooltip:AddLine("Maj + glisser : déplacer   /dz : options", 0.6, 0.6, 0.6)
    GameTooltip:Show()
end)
toggle:SetScript("OnLeave", function() GameTooltip:Hide() end)

local function ApplyPosition()
    toggle:ClearAllPoints()
    local p = DB.pos
    if p then
        toggle:SetPoint(p[1], UIParent, p[2], p[3], p[4])
    else
        toggle:SetPoint("CENTER", UIParent, "CENTER", -200, 0)
    end
end

---------------------------------------------------------------------------
-- Panneau d'options
---------------------------------------------------------------------------
local panel = CreateFrame("Frame", "DrinkZisOptions")
panel.name = "DrinkZis"
panel:Hide()

local function Label(parent, text, template)
    local fs = parent:CreateFontString(nil, "ARTWORK", template or "GameFontHighlight")
    fs:SetText(text)
    return fs
end

local function CheckBox(text, x, y, onClick)
    local cb = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
    cb:SetSize(26, 26)
    cb:SetPoint("TOPLEFT", x, y)
    cb.label = Label(cb, text)
    cb.label:SetPoint("LEFT", cb, "RIGHT", 4, 0)
    cb:SetScript("OnClick", function(self)
        if InCombatLockdown() then
            print(PREFIX .. "impossible en combat.")
            self:SetChecked(not self:GetChecked())
            return
        end
        onClick(self:GetChecked() and true or false)
    end)
    return cb
end

Label(panel, "DrinkZis", "GameFontNormalLarge"):SetPoint("TOPLEFT", 16, -16)
Label(panel, "Sac à potions flottant, rangé par catégorie.", "GameFontHighlightSmall"):SetPoint("TOPLEFT", 16, -40)

local cbAuto = CheckBox("Ouvrir automatiquement en combat, refermer après", 16, -64, function(v)
    DB.auto = v
    bag:SetAttribute("auto", v)
end)
local cbLock = CheckBox("Verrouiller la position", 16, -92, function(v) DB.locked = v end)

Label(panel, "Catégories affichées", "GameFontNormal"):SetPoint("TOPLEFT", 16, -134)
local catBoxes = {}
for i, c in ipairs(CATEGORIES) do
    local cb = CheckBox(c.label, 16 + (i - 1) * 120, -156, function(v)
        DB.hide[c.key] = not v or nil
        Rebuild()
    end)
    cb.label:SetTextColor(unpack(c.color))
    catBoxes[c.key] = cb
end

Label(panel, "Thème", "GameFontNormal"):SetPoint("TOPLEFT", 16, -198)
local themeButtons = {}
local function RefreshThemeButtons()
    for key, b in pairs(themeButtons) do
        b:SetEnabled(key ~= DB.theme) -- le thème actif apparaît grisé
    end
end
for i, t in ipairs(THEMES) do
    local b = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    b:SetSize(100, 24)
    b:SetPoint("TOPLEFT", 16 + (i - 1) * 106, -220)
    b:SetText(t.label)
    b:GetFontString():SetTextColor(unpack(t.border))
    b:SetScript("OnClick", function()
        DB.theme = t.key
        ApplyTheme()
        RefreshThemeButtons()
    end)
    themeButtons[t.key] = b
end

local resetBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
resetBtn:SetSize(160, 22)
resetBtn:SetPoint("TOPLEFT", 16, -264)
resetBtn:SetText("Réinitialiser la position")
resetBtn:SetScript("OnClick", function()
    if InCombatLockdown() then print(PREFIX .. "impossible en combat.") return end
    DB.pos = nil
    ApplyPosition()
end)

panel:SetScript("OnShow", function()
    cbAuto:SetChecked(DB.auto)
    cbLock:SetChecked(DB.locked)
    for key, cb in pairs(catBoxes) do cb:SetChecked(not DB.hide[key]) end
    RefreshThemeButtons()
end)

local settingsCategory
local function RegisterPanel()
    if Settings and Settings.RegisterCanvasLayoutCategory then
        settingsCategory = Settings.RegisterCanvasLayoutCategory(panel, panel.name)
        Settings.RegisterAddOnCategory(settingsCategory)
    elseif InterfaceOptions_AddCategory then
        InterfaceOptions_AddCategory(panel)
    end
end

local function OpenPanel()
    if settingsCategory then
        Settings.OpenToCategory(settingsCategory:GetID())
    elseif InterfaceOptionsFrame_OpenToCategory then
        InterfaceOptionsFrame_OpenToCategory(panel)
        InterfaceOptionsFrame_OpenToCategory(panel)
    end
end

---------------------------------------------------------------------------
-- Événements
---------------------------------------------------------------------------
local throttle = CreateFrame("Frame")
throttle:Hide()
throttle:SetScript("OnUpdate", function(self, e)
    self.elapsed = self.elapsed + e
    if self.elapsed > 0.2 then
        self:Hide()
        if InCombatLockdown() then
            pendingRebuild = true
            UpdateAllSlots() -- quantités et recharges : autorisé en combat
        else
            Rebuild()
        end
    end
end)
local function QueueRebuild()
    throttle.elapsed = 0
    throttle:Show()
end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("BAG_UPDATE")
events:RegisterEvent("GET_ITEM_INFO_RECEIVED")
events:RegisterEvent("BAG_UPDATE_COOLDOWN")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 ~= ADDON then return end
        InitDB()
        ApplyPosition()
        ApplyTheme()
        bag:SetAttribute("auto", DB.auto)
        if DB.open then bag:Show() end
        RegisterPanel()
    elseif event == "BAG_UPDATE_COOLDOWN" then
        UpdateAllSlots()
    elseif event == "PLAYER_REGEN_ENABLED" then
        if pendingRebuild then Rebuild() end
    else
        QueueRebuild()
    end
end)

SLASH_DRINKZIS1 = "/dz"
SLASH_DRINKZIS2 = "/drinkzis"
SlashCmdList.DRINKZIS = function(msg)
    msg = (msg or ""):lower()
    if msg == "reset" then
        if InCombatLockdown() then print(PREFIX .. "pas en combat.") return end
        DB.pos = nil
        ApplyPosition()
        print(PREFIX .. "position réinitialisée.")
    else
        OpenPanel()
    end
end
