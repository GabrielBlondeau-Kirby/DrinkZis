-- DrinkZis : un « sac » à potions flottant, rangé par catégorie.
-- Une icône ronde ouvre / ferme le sac (même en combat, via un handler sécurisé).
local ADDON = ...
local PREFIX = "|cff66ccffDrinkZis|r : "
local ICON = "Interface\\AddOns\\DrinkZis\\Media\\icon"

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
-- Langues : textes de l'interface et mots-clés de reconnaissance des potions.
-- La langue choisie ne change que l'interface ; les mots-clés de toutes les
-- langues servent ensemble au classement (voir KW plus bas).
-- Tout est comparé en minuscules ; string.lower ne touche pas aux lettres
-- accentuées (« É » reste « É »), d'où « lixir » plutôt que « élixir ».
---------------------------------------------------------------------------
local LANGS = {
    enUS = {
        name = "English",
        kw = {
            use     = { "^use:" },
            health  = { "health" },
            mana    = { "mana" },
            exclude = { "bandage" },
            buff    = { "elixir", "flask", "scroll" },
            potion  = { "potion", "healthstone", "mana" },
            combat  = { "potion" },
            energy  = { "energy" },
            cure    = { "cure", "remove" },
            antidote = { "antidote" },
            ailment = { "poison", "disease", "curse" },
        },
        ui = {
            empty = "No potions",
            cat_heal = "Health", cat_mana = "Mana", cat_combat = "Combat", cat_buff = "Buffs", cat_debuff = "Debuffs",
            theme_dark = "Dark", theme_gold = "Gold", theme_arcane = "Arcane", theme_fel = "Fel", theme_blood = "Blood", theme_wow = "WoWtesk",
            tip_click = "Click: open / close the bag",
            tip_drag = "Shift + drag: move   /dz: options",
            mm_left = "Left-click: open / close the bag",
            mm_right = "Right-click: options",
            mm_drag = "Drag: move around the minimap",
            subtitle = "Floating potion bag, sorted by category.",
            opt_auto = "Open automatically in combat, close afterwards",
            opt_lock = "Lock position",
            opt_minimap = "Show the minimap icon",
            opt_fade = "Transparent round icon out of combat (opaque on hover)",
            opt_cats = "Shown categories",
            opt_theme = "Theme",
            opt_lang = "Language",
            opt_lang_hint = "Interface language. Auto = game language.",
            lang_auto = "Auto (game)",
            opt_reset = "Reset position",
            no_combat = "not possible in combat.",
            no_options_combat = "options unavailable in combat.",
            pos_reset = "position reset.",
            mm_shown = "minimap icon shown.",
            mm_hidden = "minimap icon hidden.",
        },
    },
    frFR = {
        name = "Français",
        kw = {
            use     = { "^utiliser" },
            health  = { "points de vie" },
            mana    = { "points de mana", "mana" },
            exclude = { "bandage" },
            buff    = { "lixir", "flacon", "parchemin" },
            potion  = { "potion", "pierre de soins", "mana" },
            combat  = { "potion" },
            energy  = { "énergie" },
            cure    = { "guéri", "dissipe", "supprime", "retire", "annule" },
            antidote = { "antidote" },
            ailment = { "poison", "maladie", "malédiction" },
        },
        ui = {
            empty = "Aucune potion",
            cat_heal = "Vie", cat_mana = "Mana", cat_combat = "Combat", cat_buff = "Buffs", cat_debuff = "Debuffs",
            theme_dark = "Sombre", theme_gold = "Doré", theme_arcane = "Arcane", theme_fel = "Gangrène", theme_blood = "Sang", theme_wow = "WoWtesk",
            tip_click = "Clic : ouvrir / fermer le sac",
            tip_drag = "Maj + glisser : déplacer   /dz : options",
            mm_left = "Clic gauche : ouvrir / fermer le sac",
            mm_right = "Clic droit : options",
            mm_drag = "Glisser : déplacer autour de la minimap",
            subtitle = "Sac à potions flottant, rangé par catégorie.",
            opt_auto = "Ouvrir automatiquement en combat, refermer après",
            opt_lock = "Verrouiller la position",
            opt_minimap = "Afficher l'icône autour de la minimap",
            opt_fade = "Icône ronde transparente hors combat (opaque au survol)",
            opt_cats = "Catégories affichées",
            opt_theme = "Thème",
            opt_lang = "Langue",
            opt_lang_hint = "Langue de l'interface. Auto = langue du jeu.",
            lang_auto = "Auto (jeu)",
            opt_reset = "Réinitialiser la position",
            no_combat = "impossible en combat.",
            no_options_combat = "options indisponibles en combat.",
            pos_reset = "position réinitialisée.",
            mm_shown = "icône de la minimap affichée.",
            mm_hidden = "icône de la minimap masquée.",
        },
    },
}
local LANG_CHOICES = { "auto", "enUS", "frFR" }

-- Le classement lit les textes du client, quelle que soit la langue choisie
-- pour l'interface : on cherche donc les mots-clés de toutes les langues.
local KW = {}
for _, lang in pairs(LANGS) do
    for group, words in pairs(lang.kw) do
        KW[group] = KW[group] or {}
        for _, w in ipairs(words) do table.insert(KW[group], w) end
    end
end

local DB
local L = LANGS[GetLocale() == "frFR" and "frFR" or "enUS"]

-- Langue effective : celle choisie, sinon celle du client (anglais par défaut).
local function ResolveLang()
    local choice = DB and DB.lang or "auto"
    if LANGS[choice] then return LANGS[choice] end
    return LANGS[GetLocale() == "frFR" and "frFR" or "enUS"]
end

local function T(key) return L.ui[key] or LANGS.enUS.ui[key] or key end

-- Textes à retraduire quand on change de langue : { objet, clé }.
local localized = {}
local function Loc(obj, key)
    table.insert(localized, { obj, key })
    obj:SetText(T(key))
    return obj
end

---------------------------------------------------------------------------
-- Catégories et thèmes
---------------------------------------------------------------------------
local CATEGORIES = {
    { key = "heal",   icon = "Interface\\Icons\\Spell_Holy_Heal",             color = { 0.95, 0.25, 0.25 } },
    { key = "mana",   icon = "Interface\\Icons\\Spell_Nature_ManaRegenTotem", color = { 0.30, 0.55, 1.00 } },
    { key = "combat", icon = "Interface\\Icons\\Ability_DualWield",           color = { 1.00, 0.60, 0.10 } },
    { key = "buff",   icon = "Interface\\Icons\\Spell_Holy_WordFortitude",    color = { 0.70, 0.40, 1.00 } },
    { key = "debuff", icon = "Interface\\Icons\\Spell_Nature_NullifyPoison",  color = { 0.40, 0.85, 0.30 } },
}
local CAT_BY_KEY = {}
for _, c in ipairs(CATEGORIES) do CAT_BY_KEY[c.key] = c end

local THEMES = {
    { key = "dark",   bg = { 0, 0, 0, 0.80 },          border = { 0.55, 0.55, 0.55 } },
    { key = "gold",   bg = { 0.10, 0.07, 0.03, 0.88 }, border = { 1.00, 0.80, 0.20 } },
    { key = "arcane", bg = { 0.05, 0.03, 0.15, 0.88 }, border = { 0.65, 0.45, 1.00 } },
    { key = "fel",    bg = { 0.02, 0.10, 0.02, 0.88 }, border = { 0.35, 1.00, 0.20 } },
    { key = "blood",  bg = { 0.12, 0.02, 0.02, 0.88 }, border = { 0.90, 0.15, 0.15 } },
    -- « WoWtesk » : cadre de dialogue de l'interface Blizzard, textures d'origine non teintées.
    { key = "wow", bg = { 1, 1, 1, 1 }, border = { 1, 1, 1 }, ring = { 1, 1, 1 }, label = { 1, 0.82, 0 },
      backdrop = {
          bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
          edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
          tile = true, tileSize = 32, edgeSize = 20,
          insets = { left = 5, right = 5, top = 5, bottom = 5 },
      } },
}
local THEME_BY_KEY = {}
for _, t in ipairs(THEMES) do THEME_BY_KEY[t.key] = t end

local function InitDB()
    DrinkZisDB = DrinkZisDB or {}
    DB = DrinkZisDB
    if DB.auto == nil then DB.auto = true end
    DB.theme = THEME_BY_KEY[DB.theme or ""] and DB.theme or "dark"
    DB.hide = DB.hide or {}
    DB.minimap = DB.minimap or { angle = 200, hide = false }
    DB.lang = LANGS[DB.lang or ""] and DB.lang or "auto"
end

---------------------------------------------------------------------------
-- Classement des objets
---------------------------------------------------------------------------
local FOOD, DRINK = SpellName(433), SpellName(430)

local scan = CreateFrame("GameTooltip", "DrinkZisScanTip", nil, "GameTooltipTemplate")

-- Retire les codes couleur / liens et les espaces de tête, passe en minuscules.
local function CleanLine(text)
    text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|H.-|h(.-)|h", "%1")
    return (text:gsub("^%s+", ""):lower())
end

-- Lignes de l'infobulle (sauf le nom), nettoyées ; nil si l'objet n'est pas en cache.
local function TooltipLines(itemID)
    local lines = {}
    if C_TooltipInfo and C_TooltipInfo.GetItemByID then
        local data = C_TooltipInfo.GetItemByID(itemID)
        if not data or not data.lines or #data.lines == 0 then return nil end
        for i = 2, #data.lines do
            local text = data.lines[i].leftText
            if text and text ~= "" then table.insert(lines, CleanLine(text)) end
        end
        return lines
    end
    scan:SetOwner(WorldFrame, "ANCHOR_NONE")
    scan:ClearLines()
    scan:SetHyperlink("item:" .. itemID)
    local n = scan:NumLines()
    if n == 0 then return nil end
    for i = 2, n do
        local fs = _G["DrinkZisScanTipTextLeft" .. i]
        local text = fs and fs:GetText()
        if text and text ~= "" then table.insert(lines, CleanLine(text)) end
    end
    return lines
end

-- Ligne « Utiliser : … » ; à défaut, toute la description (certaines potions
-- n'ont pas ce préfixe, ou le client le formate autrement). nil si pas en cache.
-- 2e valeur : true si la vraie ligne « Utiliser : » a été trouvée.
local function UseLine(itemID)
    local lines = TooltipLines(itemID)
    if not lines then return nil end
    for _, text in ipairs(lines) do
        for _, pattern in ipairs(KW.use) do
            if text:find(pattern) then return text, true end
        end
    end
    return table.concat(lines, " "), false
end

local function Has(s, words)
    for _, w in ipairs(words) do
        if s:find(w, 1, true) then return true end
    end
    return false
end

local cache = {} -- itemID -> clé de catégorie, ou false
-- À la connexion, le sort et la description d'un objet arrivent parfois après
-- son nom : un classement fait sans eux n'est pas mis en cache, on réessaie.
local firstTry, RETRY_FOR = {}, 20 -- itemID -> GetTime() du 1er essai ; secondes

-- Renvoie la catégorie, false si ce n'est pas une potion, nil si pas encore chargé.
-- 2e valeur : true si le résultat est provisoire (à refaire plus tard).
local function Classify(itemID)
    if cache[itemID] ~= nil then return cache[itemID] end
    local name, _, _, _, _, _, _, _, _, _, _, classID = GetItemInfoCompat(itemID)
    if not name then return nil end
    local result, complete = false, true
    local spell = GetItemSpellCompat(itemID)
    if classID == 0 and not spell then complete = false end
    if classID == 0 and spell and spell ~= FOOD and spell ~= DRINK then
        local use, found = UseLine(itemID)
        if use == nil then return nil end
        complete = found
        local n, kw = name:lower(), KW
        if Has(n, kw.exclude) then
            result = false
        elseif (Has(use, kw.cure) and Has(use, kw.ailment)) or Has(use, kw.antidote) then
            -- Anti-venin, antidotes, potions de purification : poison / maladie / malédiction.
            result = "debuff"
        elseif Has(n, kw.buff) then
            result = "buff"
        elseif Has(n, kw.potion) then
            if Has(use, kw.health) then
                result = "heal"
            elseif Has(use, kw.mana) then
                result = "mana"
            elseif Has(n, kw.combat) then
                result = "combat"
            end
        elseif Has(use, kw.energy) then
            -- Thé de chardon et autres objets qui rendent de l'énergie.
            result = "combat"
        end
    end
    if not complete then
        firstTry[itemID] = firstTry[itemID] or GetTime()
        if GetTime() - firstTry[itemID] < RETRY_FOR then return result, true end
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
                seen[id] = true
                local cat, provisional = Classify(id)
                if cat == nil or provisional then missing = true end
                if cat then
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

local emptyText = Loc(bag:CreateFontString(nil, "OVERLAY", "GameFontDisable"), "empty")

toggle:SetFrameRef("bag", bag)
toggle:SetAttribute("_onclick", [[
    local bag = self:GetFrameRef("bag")
    bag:SetAttribute("autoopened", nil)
    if bag:IsShown() then bag:Hide() else bag:Show() end
]])

-- Ouverture auto en combat / fermeture à la sortie (seulement si c'est l'auto qui a ouvert).
-- États en toutes lettres : les clients récents convertissent "1" / "0" en nombres,
-- et la comparaison avec une chaîne échouait.
bag:SetAttribute("_onstate-combat", [[
    if not self:GetAttribute("auto") then return end
    if newstate == "on" then
        if not self:IsShown() then
            self:SetAttribute("autoopened", 1)
            self:Show()
        end
    elseif self:GetAttribute("autoopened") then
        self:Hide()
        self:SetAttribute("autoopened", nil)
    end
]])
RegisterStateDriver(bag, "combat", "[combat] on; off")

-- On ne mémorise que les ouvertures / fermetures manuelles.
bag:HookScript("OnShow", function(self) if DB and not self:GetAttribute("autoopened") then DB.open = true end end)
bag:HookScript("OnHide", function(self) if DB and not self:GetAttribute("autoopened") then DB.open = false end end)

local DEFAULT_BACKDROP = {
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 14,
    insets = { left = 3, right = 3, top = 3, bottom = 3 },
}

local function ApplyTheme()
    local t = THEME_BY_KEY[DB.theme]
    if bag.SetBackdrop then
        bag:SetBackdrop(t.backdrop or DEFAULT_BACKDROP)
        bag:SetBackdropColor(unpack(t.bg))
        bag:SetBackdropBorderColor(unpack(t.border))
    end
    tRing:SetVertexColor(unpack(t.ring or t.border))
end

---------------------------------------------------------------------------
-- Emplacements (boutons sécurisés, créés / placés hors combat uniquement)
---------------------------------------------------------------------------
local SLOT, GAP, COLS, CAT_ICON = 34, 4, 6, 24
local LABEL_W = CAT_ICON + 10 -- colonne des icônes de catégorie
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
        GameTooltip:AddLine("DrinkZis — " .. T("cat_" .. c.key), c.color[1], c.color[2], c.color[3])
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)

    slots[i] = b
    return b
end

-- Icône de catégorie (cadre non sécurisé) : bordure colorée + nom en infobulle.
local function GetLabel(i)
    local l = labels[i]
    if l then return l end
    l = CreateFrame("Frame", nil, bag)
    l:SetSize(CAT_ICON, CAT_ICON)
    l:EnableMouse(true)

    l.border = l:CreateTexture(nil, "BACKGROUND")
    l.border:SetPoint("TOPLEFT", -2, 2)
    l.border:SetPoint("BOTTOMRIGHT", 2, -2)
    l.border:SetColorTexture(1, 1, 1, 1)

    l.icon = l:CreateTexture(nil, "ARTWORK")
    l.icon:SetAllPoints()
    l.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    l:SetScript("OnEnter", function(self)
        local c = CAT_BY_KEY[self.cat]
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText(T("cat_" .. c.key), c.color[1], c.color[2], c.color[3])
        GameTooltip:Show()
    end)
    l:SetScript("OnLeave", function() GameTooltip:Hide() end)

    labels[i] = l
    return l
end

local pendingRebuild, retryScheduled = false, false

local function Rebuild()
    if not DB then return end
    if InCombatLockdown() then pendingRebuild = true return end
    pendingRebuild = false

    local byCat, missing = CollectItems()
    -- Des objets pas encore (ou pas entièrement) chargés : on refait un tour plus tard.
    if missing and not retryScheduled and C_Timer then
        retryScheduled = true
        C_Timer.After(2, function()
            retryScheduled = false
            Rebuild()
        end)
    end
    local x0 = TOGGLE / 2 + 10 -- dégage l'icône ronde qui chevauche le coin
    local y, nSlot, nLabel, maxCols = -10, 0, 0, 0

    for _, c in ipairs(CATEGORIES) do
        local list = byCat[c.key]
        if list and not DB.hide[c.key] then
            nLabel = nLabel + 1
            local l = GetLabel(nLabel)
            l.cat = c.key
            l.icon:SetTexture(c.icon)
            l.border:SetVertexColor(unpack(c.color))
            l:ClearAllPoints()
            l:SetPoint("LEFT", bag, "TOPLEFT", x0 + 2, y - SLOT / 2)
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
-- Option : icône ronde transparente hors combat (opaque au survol et en combat).
-- SetAlpha reste permis sur un cadre sécurisé, même en combat.
local FADED_ALPHA = 0.3
local function UpdateToggleAlpha(inCombat)
    if inCombat == nil then inCombat = InCombatLockdown() end
    local faded = DB and DB.fade and not inCombat and not toggle:IsMouseOver()
    toggle:SetAlpha(faded and FADED_ALPHA or 1)
end

toggle:SetScript("OnEnter", function(self)
    self:SetAlpha(1)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText("DrinkZis", 0.4, 0.8, 1)
    GameTooltip:AddLine(T("tip_click"), 1, 1, 1)
    GameTooltip:AddLine(T("tip_drag"), 0.6, 0.6, 0.6)
    GameTooltip:Show()
end)
toggle:SetScript("OnLeave", function()
    GameTooltip:Hide()
    UpdateToggleAlpha()
end)

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

-- key : clé de traduction (Loc) ; raw : texte fixe.
local function Label(parent, key, template, raw)
    local fs = parent:CreateFontString(nil, "ARTWORK", template or "GameFontHighlight")
    if raw then fs:SetText(raw) else Loc(fs, key) end
    return fs
end

local function CheckBox(key, x, y, onClick)
    local cb = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
    cb:SetSize(26, 26)
    cb:SetPoint("TOPLEFT", x, y)
    cb.label = Label(cb, key)
    cb.label:SetPoint("LEFT", cb, "RIGHT", 4, 0)
    cb:SetScript("OnClick", function(self)
        if InCombatLockdown() then
            print(PREFIX .. T("no_combat"))
            self:SetChecked(not self:GetChecked())
            return
        end
        onClick(self:GetChecked() and true or false)
    end)
    return cb
end

Label(panel, nil, "GameFontNormalLarge", "DrinkZis"):SetPoint("TOPLEFT", 16, -16)
Label(panel, "subtitle", "GameFontHighlightSmall"):SetPoint("TOPLEFT", 16, -40)

local cbAuto = CheckBox("opt_auto", 16, -64, function(v)
    DB.auto = v
    bag:SetAttribute("auto", v)
end)
local cbLock = CheckBox("opt_lock", 16, -92, function(v) DB.locked = v end)
local SetMinimapShown -- défini plus bas
local cbMinimap = CheckBox("opt_minimap", 16, -120, function(v) SetMinimapShown(v) end)
local cbFade = CheckBox("opt_fade", 16, -148, function(v)
    DB.fade = v
    UpdateToggleAlpha()
end)

Label(panel, "opt_cats", "GameFontNormal"):SetPoint("TOPLEFT", 16, -190)
local catBoxes = {}
for i, c in ipairs(CATEGORIES) do
    local cb = CheckBox("cat_" .. c.key, 16 + (i - 1) * 110, -212, function(v)
        DB.hide[c.key] = not v or nil
        Rebuild()
    end)
    cb.label:SetTextColor(unpack(c.color))
    catBoxes[c.key] = cb
end

Label(panel, "opt_theme", "GameFontNormal"):SetPoint("TOPLEFT", 16, -254)
local themeButtons = {}
local function RefreshThemeButtons()
    for key, b in pairs(themeButtons) do
        b:SetEnabled(key ~= DB.theme) -- le thème actif apparaît grisé
    end
end
for i, t in ipairs(THEMES) do
    local b = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    b:SetSize(88, 24)
    b:SetPoint("TOPLEFT", 16 + (i - 1) * 94, -276)
    Loc(b, "theme_" .. t.key)
    b:GetFontString():SetTextColor(unpack(t.label or t.border))
    b:SetScript("OnClick", function()
        DB.theme = t.key
        ApplyTheme()
        RefreshThemeButtons()
    end)
    themeButtons[t.key] = b
end

Label(panel, "opt_lang", "GameFontNormal"):SetPoint("TOPLEFT", 16, -320)
Label(panel, "opt_lang_hint", "GameFontHighlightSmall"):SetPoint("TOPLEFT", 90, -322)
local langButtons = {}
local function RefreshLangButtons()
    for key, b in pairs(langButtons) do
        b:SetEnabled(key ~= DB.lang) -- la langue active apparaît grisée
    end
end

-- Change la langue de l'interface (le classement des potions n'en dépend pas).
local function ApplyLanguage()
    L = ResolveLang()
    for _, entry in ipairs(localized) do entry[1]:SetText(T(entry[2])) end
end

for i, choice in ipairs(LANG_CHOICES) do
    local b = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    b:SetSize(100, 24)
    b:SetPoint("TOPLEFT", 16 + (i - 1) * 106, -342)
    if LANGS[choice] then b:SetText(LANGS[choice].name) else Loc(b, "lang_auto") end
    b:SetScript("OnClick", function()
        DB.lang = choice
        ApplyLanguage()
        RefreshLangButtons()
    end)
    langButtons[choice] = b
end

local resetBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
resetBtn:SetSize(180, 22)
resetBtn:SetPoint("TOPLEFT", 16, -386)
Loc(resetBtn, "opt_reset")
resetBtn:SetScript("OnClick", function()
    if InCombatLockdown() then print(PREFIX .. T("no_combat")) return end
    DB.pos = nil
    ApplyPosition()
end)

panel:SetScript("OnShow", function()
    cbAuto:SetChecked(DB.auto)
    cbLock:SetChecked(DB.locked)
    cbMinimap:SetChecked(not DB.minimap.hide)
    cbFade:SetChecked(DB.fade)
    for key, cb in pairs(catBoxes) do cb:SetChecked(not DB.hide[key]) end
    RefreshThemeButtons()
    RefreshLangButtons()
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
-- Icône autour de la minimap
-- Clic gauche : ouvre / ferme le sac (sécurisé, marche en combat).
-- Clic droit : options. Glisser : faire tourner autour de la minimap.
---------------------------------------------------------------------------
local minimapBtn = CreateFrame("Button", "DrinkZisMinimapButton", Minimap, "SecureHandlerClickTemplate")
minimapBtn:SetSize(31, 31)
minimapBtn:SetFrameStrata("MEDIUM")
minimapBtn:SetFrameLevel(8)
minimapBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
minimapBtn:RegisterForDrag("LeftButton")
minimapBtn:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

local mmBg = minimapBtn:CreateTexture(nil, "BACKGROUND")
mmBg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
mmBg:SetSize(20, 20)
mmBg:SetPoint("TOPLEFT", 7, -5)

local mmIcon = minimapBtn:CreateTexture(nil, "ARTWORK")
mmIcon:SetTexture(ICON)
mmIcon:SetSize(17, 17)
mmIcon:SetPoint("TOPLEFT", 7, -6)
mmIcon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

local mmBorder = minimapBtn:CreateTexture(nil, "OVERLAY")
mmBorder:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
mmBorder:SetSize(53, 53)
mmBorder:SetPoint("TOPLEFT")

minimapBtn:SetFrameRef("bag", bag)
minimapBtn:SetAttribute("_onclick", [[
    if button ~= "LeftButton" then return end
    local bag = self:GetFrameRef("bag")
    bag:SetAttribute("autoopened", nil)
    if bag:IsShown() then bag:Hide() else bag:Show() end
]])
minimapBtn:HookScript("OnClick", function(_, mouse)
    if mouse ~= "RightButton" then return end
    if InCombatLockdown() then print(PREFIX .. T("no_options_combat")) return end
    OpenPanel()
end)

local function PlaceMinimapButton()
    local a = math.rad(DB.minimap.angle)
    local r = Minimap:GetWidth() / 2 + 5
    minimapBtn:ClearAllPoints()
    minimapBtn:SetPoint("CENTER", Minimap, "CENTER", math.cos(a) * r, math.sin(a) * r)
end

SetMinimapShown = function(shown)
    DB.minimap.hide = not shown
    minimapBtn:SetShown(shown)
end

-- Bouton sécurisé : on ne le déplace qu'hors combat.
minimapBtn:SetScript("OnDragStart", function(self)
    if InCombatLockdown() then return end
    self:SetScript("OnUpdate", function()
        if InCombatLockdown() then self:SetScript("OnUpdate", nil) return end
        local mx, my = Minimap:GetCenter()
        local px, py = GetCursorPosition()
        local scale = Minimap:GetEffectiveScale()
        DB.minimap.angle = math.deg(math.atan2(py / scale - my, px / scale - mx))
        PlaceMinimapButton()
    end)
end)
minimapBtn:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)

minimapBtn:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:SetText("DrinkZis", 0.4, 0.8, 1)
    GameTooltip:AddLine(T("mm_left"), 1, 1, 1)
    GameTooltip:AddLine(T("mm_right"), 1, 1, 1)
    GameTooltip:AddLine(T("mm_drag"), 0.6, 0.6, 0.6)
    GameTooltip:Show()
end)
minimapBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

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
events:RegisterEvent("PLAYER_REGEN_DISABLED")
events:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 ~= ADDON then return end
        InitDB()
        ApplyLanguage()
        ApplyPosition()
        ApplyTheme()
        bag:SetAttribute("auto", DB.auto)
        if DB.open then bag:Show() end
        PlaceMinimapButton()
        minimapBtn:SetShown(not DB.minimap.hide)
        UpdateToggleAlpha()
        RegisterPanel()
    elseif event == "BAG_UPDATE_COOLDOWN" then
        UpdateAllSlots()
    elseif event == "PLAYER_REGEN_DISABLED" then
        UpdateToggleAlpha(true)
    elseif event == "PLAYER_REGEN_ENABLED" then
        UpdateToggleAlpha(false)
        if pendingRebuild then Rebuild() end
    else
        QueueRebuild()
    end
end)

-- Fenêtre avec une zone de texte sélectionnable : le chat ne se copie pas.
local copyFrame
local function ShowCopyWindow(text)
    if not copyFrame then
        local f = CreateFrame("Frame", "DrinkZisCopyFrame", UIParent)
        f:SetSize(620, 380)
        f:SetPoint("CENTER")
        f:SetFrameStrata("DIALOG")
        f:SetMovable(true)
        f:EnableMouse(true)
        f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", f.StartMoving)
        f:SetScript("OnDragStop", f.StopMovingOrSizing)
        local bg = f:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0, 0, 0, 0.9)
        local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        title:SetPoint("TOPLEFT", 12, -10)
        title:SetText("DrinkZis debug — Ctrl+A, Ctrl+C")
        local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
        close:SetPoint("TOPRIGHT", 2, 2)
        local scroll = CreateFrame("ScrollFrame", "DrinkZisCopyScroll", f, "UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT", 12, -32)
        scroll:SetPoint("BOTTOMRIGHT", -32, 12)
        local edit = CreateFrame("EditBox", nil, scroll)
        edit:SetMultiLine(true)
        edit:SetAutoFocus(false)
        edit:SetFontObject(ChatFontNormal)
        edit:SetWidth(570)
        edit:SetScript("OnEscapePressed", function() f:Hide() end)
        scroll:SetScrollChild(edit)
        f.edit = edit
        tinsert(UISpecialFrames, "DrinkZisCopyFrame") -- Échap ferme la fenêtre
        copyFrame = f
    end
    copyFrame.edit:SetText(text)
    copyFrame:Show()
    copyFrame.edit:SetFocus()
    copyFrame.edit:HighlightText()
end

SLASH_DRINKZIS1 = "/dz"
SLASH_DRINKZIS2 = "/drinkzis"
SlashCmdList.DRINKZIS = function(msg)
    msg = (msg or ""):lower()
    if msg == "reset" then
        if InCombatLockdown() then print(PREFIX .. T("no_combat")) return end
        DB.pos = nil
        ApplyPosition()
        print(PREFIX .. T("pos_reset"))
    elseif msg == "debug" then
        -- Reclasse tout et affiche ce que l'addon lit pour chaque consommable.
        wipe(cache)
        local seen, out = {}, {}
        for b = 0, 4 do
            for s = 1, (GetNumSlots(b) or 0) do
                local id = GetItemID(b, s)
                if id and not seen[id] then
                    seen[id] = true
                    local name, _, _, _, _, _, _, _, _, _, _, classID = GetItemInfoCompat(id)
                    if classID == 0 then
                        local use = UseLine(id)
                        table.insert(out, ("%s [%d] → %s | spell=%s | use=%s"):format(
                            name, id, tostring((Classify(id))),
                            tostring((GetItemSpellCompat(id))), use and use:sub(1, 200) or "nil (pas en cache)"))
                    end
                end
            end
        end
        ShowCopyWindow(#out > 0 and table.concat(out, "\n") or "(aucun consommable)")
        QueueRebuild()
    elseif msg == "minimap" then
        if InCombatLockdown() then print(PREFIX .. T("no_combat")) return end
        SetMinimapShown(DB.minimap.hide)
        print(PREFIX .. T(DB.minimap.hide and "mm_hidden" or "mm_shown"))
    else
        OpenPanel()
    end
end
