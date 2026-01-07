--[[
    REALISTIC LOADS MOD - MAIN FILE
    =============================================================
    Main coordination file for wind and tilt loss systems
]]

print("[RealisticLoads]: ========================================");
print("[RealisticLoads]: Main specialization file STARTING to load...");
print("[RealisticLoads]: ========================================");

-- Ensure RealisticLoads namespace exists
if RealisticLoads == nil then
    RealisticLoads = {};
end

local modName = g_currentModName;
local modDirectory = g_currentModDirectory;

print("[RealisticLoads]: ========================================");
print("[RealisticLoads]: Main specialization file loading...");
print(string.format("[RealisticLoads]: Mod: %s, Dir: %s", modName or "UNKNOWN", modDirectory or "UNKNOWN"));
print("[RealisticLoads]: ========================================");

-- Verify Common utilities are loaded
if RealisticLoadsCommon == nil then
    print("[RealisticLoads]: ERROR - RealisticLoadsCommon not found! Make sure it loads before this file.");
end

-- Event files should be loaded via extraSourceFiles in modDesc.xml
-- Verify they exist (they should already be loaded)
if RealisticLoadsTiltEvent == nil then
    print("[RealisticLoads]: WARNING - RealisticLoadsTiltEvent not found!");
end
if RealisticLoadsWindEvent == nil then
    print("[RealisticLoads]: WARNING - RealisticLoadsWindEvent not found!");
end
if RealisticLoadsTiltEvent ~= nil and RealisticLoadsWindEvent ~= nil then
    print("[RealisticLoads]: Event files are loaded correctly");
end

-- Load modDesc safely (might fail if modDesc.xml doesn't exist yet)
RealisticLoads.modDesc = nil;
if modDirectory and fileExists(modDirectory .. "modDesc.xml") then
    RealisticLoads.modDesc = loadXMLFile("modDesc", modDirectory .. "modDesc.xml");
    print("[RealisticLoads]: modDesc.xml loaded successfully");
else
    print("[RealisticLoads]: WARNING - modDesc.xml not found or modDirectory is nil");
end

-- Configuration defaults
RealisticLoads.DEBUG_MODE = false;
RealisticLoads.modConfigDone = false;
RealisticLoads.fillTypesDetected = false;

-- Tilt loss configuration
RealisticLoads.ENABLE_TILT_LOSS = true;
RealisticLoads.TILT_START_ANGLE = math.rad(15);
RealisticLoads.TILT_END_ANGLE = math.rad(90);
RealisticLoads.TILT_COVER_BONUS_ANGLE = math.rad(15);
RealisticLoads.TILT_COVER_LOST_ANGLE = math.rad(60);
RealisticLoads.TILT_CHECK_CYCLE_MS = 200;

-- Wind loss configuration
RealisticLoads.ENABLE_WIND_LOSS = true;
RealisticLoads.MIN_SPEED_TO_BLOW = 5.56;
RealisticLoads.CONSIDER_WIND = true;
RealisticLoads.BLOW_FACTOR_GLOBAL = 1.0;
RealisticLoads.SYNC_TIME_INTERVAL_MS = 1000;
RealisticLoads.STANDARD_MASS_PER_LITER = 0.0006;
RealisticLoads.STANDARD_BLOW_FACTOR = 0.5;

-- Data storage
RealisticLoads.fillTypesIndexToName = {};
RealisticLoads.applicableFillTypes = {};
RealisticLoads.vehicleTypesToExclude = {};

-- Event listeners
RealisticLoads.USED_EVENT_LISTENERS = {
    "onUpdate",
    "onDraw"
};

-- HUD data
RealisticLoads.hudData = {
    hudTextPosX = 0.99,
    hudTextPosY = 0.85,
    hudTextSize = 0.015 * g_gameSettings.uiScale
};

-- Initialize mod data (called once, deferred until managers are ready)
function RealisticLoads.initModData()
    if RealisticLoads.modConfigDone then
        return;
    end

    print("[RealisticLoads]: initModData called");

    -- Load XML config first
    if RealisticLoads.modDesc ~= nil then
        RealisticLoads:getXmlConfig();
        print("[RealisticLoads]: XML config loaded");
    else
        print("[RealisticLoads]: WARNING - modDesc is nil, using defaults");
    end

    -- This ensures fill types are loaded before we try to detect them
    print("[RealisticLoads]: Fill type detection will happen after FillTypeManager.loadMapData");

    if RealisticLoads.modDesc ~= nil then
        delete(RealisticLoads.modDesc);
        RealisticLoads.modDesc = nil;
    end
end


-- Load XML configuration
function RealisticLoads:getXmlConfig()
    local modDesc = RealisticLoads.modDesc;
    if modDesc == nil then
        return; -- No modDesc available, use defaults
    end

    -- General settings
    RealisticLoads.DEBUG_MODE = Utils.getNoNil(getXMLBool(modDesc, "modDesc.realisticLoadsConfigurations#debugMode"), RealisticLoads.DEBUG_MODE);

    -- Wind loss settings
    RealisticLoads.ENABLE_WIND_LOSS = Utils.getNoNil(getXMLBool(modDesc, "modDesc.realisticLoadsConfigurations#enableWindLoss"), RealisticLoads.ENABLE_WIND_LOSS);
    RealisticLoads.CONSIDER_WIND = Utils.getNoNil(getXMLBool(modDesc, "modDesc.realisticLoadsConfigurations#considerWindSpeed"), RealisticLoads.CONSIDER_WIND);
    RealisticLoads.MIN_SPEED_TO_BLOW = Utils.getNoNil(getXMLFloat(modDesc, "modDesc.realisticLoadsConfigurations#minBlowSpeed"), RealisticLoads.MIN_SPEED_TO_BLOW);
    RealisticLoads.BLOW_FACTOR_GLOBAL = Utils.getNoNil(getXMLFloat(modDesc, "modDesc.realisticLoadsConfigurations#blowFactorGlobal"), RealisticLoads.BLOW_FACTOR_GLOBAL);
    RealisticLoads.BLOW_FACTOR_GLOBAL = math.max(RealisticLoads.BLOW_FACTOR_GLOBAL, 0);

    -- Fill type configurations
    local specializationNumber = 0;
    while true do
        local key = string.format("modDesc.realisticLoadsConfigurations.fillTypeConfigurations.fillTypeConfiguration(%d)", specializationNumber);
        if not hasXMLProperty(modDesc, key) then
            break;
        end

        local fillTypeName = (Utils.getNoNil(getXMLString(modDesc, key .. "#fillTypeName"), "")):upper();
        if fillTypeName ~= "" then
            local fillTypeInclude = Utils.getNoNil(getXMLBool(modDesc, key .. "#fillTypeInclude"), false);
            local fillTypeExclude = Utils.getNoNil(getXMLBool(modDesc, key .. "#fillTypeExclude"), false);
            local fillTypeBlowFactor = Utils.getNoNil(getXMLFloat(modDesc, key .. "#fillTypeBlowFactor"), RealisticLoads.STANDARD_BLOW_FACTOR);

            if fillTypeInclude and fillTypeExclude then
                fillTypeInclude = false;
            end

            if fillTypeExclude then
                if RealisticLoads.applicableFillTypes[fillTypeName] ~= nil then
                    RealisticLoads.fillTypesIndexToName[RealisticLoads.applicableFillTypes[fillTypeName].index] = nil;
                    RealisticLoads.applicableFillTypes[fillTypeName] = nil;
                    -- Note: blowFactors will be in RealisticLoadsWindLoss.lua
                end
            elseif fillTypeInclude then
                if g_fillTypeManager ~= nil and g_fillTypeManager.getFillTypeByName ~= nil then
                    local fillType = g_fillTypeManager:getFillTypeByName(fillTypeName);
                    if fillType ~= nil and fillType.name ~= nil then
                        RealisticLoads.applicableFillTypes[fillType.name] = fillType;
                        RealisticLoads.fillTypesIndexToName[fillType.index] = fillType.name;
                    end
                end
            end
        end

        specializationNumber = specializationNumber + 1;
    end

    -- Vehicle type configurations
    specializationNumber = 0;
    while true do
        local key = string.format("modDesc.realisticLoadsConfigurations.vehicleTypeConfigurations.vehicleTypeConfiguration(%d)", specializationNumber);
        if not hasXMLProperty(modDesc, key) then
            break;
        end

        local vehicleTypeName = (Utils.getNoNil(getXMLString(modDesc, key .. "#fullVehicleName"), "")):upper();
        if vehicleTypeName ~= "" then
            local vehicleTypeExclude = Utils.getNoNil(getXMLBool(modDesc, key .. "#vehicleExclude"), false);
            if vehicleTypeExclude then
                RealisticLoads.vehicleTypesToExclude[vehicleTypeName] = true;
            end
        end

        specializationNumber = specializationNumber + 1;
    end
end

-- Prerequisites check
function RealisticLoads.prerequisitesPresent(specializations)
    return SpecializationUtil.hasSpecialization(FillUnit, specializations) and
            SpecializationUtil.hasSpecialization(FillVolume, specializations) and
            SpecializationUtil.hasSpecialization(Dischargeable, specializations) and
            SpecializationUtil.hasSpecialization(Wheels, specializations);
end

-- Init specialization (called without arguments by SpecializationManager)
function RealisticLoads.initSpecialization()
    -- This is called during mod loading to initialize the specialization
    print("[RealisticLoads]: ========================================");
    print("[RealisticLoads]: initSpecialization CALLED!");
    print("[RealisticLoads]: ========================================");

    -- Initialize XML config
    if RealisticLoads.modDesc ~= nil then
        RealisticLoads:getXmlConfig();
        print("[RealisticLoads]: XML config loaded");
    end

    -- Note: FillTypeManager.loadMapData hook is set up in registerRealisticLoads.lua
    -- This ensures the hook is set up before FillTypeManager loads map data

    print("[RealisticLoads]: initSpecialization complete");
    -- Note: registerFunctions and registerEventListeners are called separately by TypeManager system
end

-- Register event listeners
function RealisticLoads.registerEventListeners(vehicleType)
    for _, functionName in ipairs(RealisticLoads.USED_EVENT_LISTENERS) do
        SpecializationUtil.registerEventListener(vehicleType, functionName, RealisticLoads);
    end
    SpecializationUtil.registerEventListener(vehicleType, "onLoad", RealisticLoads);
    SpecializationUtil.registerEventListener(vehicleType, "onLoadFinished", RealisticLoads);
    SpecializationUtil.registerEventListener(vehicleType, "onDelete", RealisticLoads);
end

-- Register functions
function RealisticLoads.registerFunctions(vehicleType)
    -- Safety check: ensure vehicleType has functions property
    if vehicleType == nil then
        print("[RealisticLoads]: ERROR - vehicleType is nil in registerFunctions");
        return;
    end
    if vehicleType.functions == nil then
        print("[RealisticLoads]: ERROR - vehicleType.functions is nil in registerFunctions, vehicleType might not be ready yet");
        return;
    end
    
    -- Register common functions
    if RealisticLoadsCommon ~= nil then
        SpecializationUtil.registerFunction(vehicleType, "getVehicleIsSupportedByRealisticLoads", RealisticLoadsCommon.getVehicleIsSupportedByRealisticLoads);
        SpecializationUtil.registerFunction(vehicleType, "isFillUnitExposed", function(self, fillUnitIndex)
            return RealisticLoadsCommon.isFillUnitExposed(self, fillUnitIndex);
        end);
        SpecializationUtil.registerFunction(vehicleType, "getFillTypeProperties", function(self, fillTypeIndex)
            return RealisticLoadsCommon.getFillTypeProperties(fillTypeIndex);
        end);
    end
    
    -- Register wind loss functions
    if RealisticLoadsWindLoss ~= nil then
        SpecializationUtil.registerFunction(vehicleType, "calculateBlowRates", function(self, airSpeed, fillUnits)
            return RealisticLoadsWindLoss.calculateBlowRates(self, airSpeed, fillUnits);
        end);
        SpecializationUtil.registerFunction(vehicleType, "calculateCurrentRelativeAirSpeed", function(self)
            local spec = self.spec_realisticLoads;
            return RealisticLoadsWindLoss.calculateCurrentRelativeAirSpeed(self, spec);
        end);
        SpecializationUtil.registerFunction(vehicleType, "blowFromFillUnit", function(self, fillUnitIndex, newVol, sendNoEvent, unloadInfo)
            return RealisticLoadsWindLoss.blowFromFillUnit(self, fillUnitIndex, newVol, sendNoEvent, unloadInfo);
        end);
    end
    
end

-- Initialize mod on vehicle
function RealisticLoads.initModOnVehicle(vehicle)
    if vehicle == nil then
        if RealisticLoads.DEBUG_MODE then
            print("[RealisticLoads]: ERROR - initModOnVehicle called with nil vehicle");
        end
        return;
    end

    -- Initialize spec if it doesn't exist
    if vehicle.spec_realisticLoads == nil then
        vehicle.spec_realisticLoads = {};
    end
    local spec = vehicle.spec_realisticLoads;

    -- Skip if already initialized
    if spec.modInitialized then
        return;
    end

    -- Ensure mod data is initialized (deferred until managers are ready)
    if not RealisticLoads.modConfigDone then
        RealisticLoads.initModData();
        -- If still not done, managers might not be ready - vehicle will be skipped for now
        if not RealisticLoads.modConfigDone then
            if RealisticLoads.DEBUG_MODE then
                print("[RealisticLoads]: Mod config not ready yet, deferring initialization");
            end
            spec.modInitialized = false;
            spec.vehicleSupported = false;
            return;
        end
    end

    -- Initialize shared spec fields using Common
    if RealisticLoadsCommon ~= nil then
        RealisticLoadsCommon.initSpecFields(vehicle, spec);
    else
        print("[RealisticLoads]: ERROR - RealisticLoadsCommon not available");
        spec.modInitialized = false;
        spec.vehicleSupported = false;
        return;
    end

    -- Initialize wind loss spec fields (if module exists)
    if RealisticLoadsWindLoss ~= nil and RealisticLoadsWindLoss.initSpecFields ~= nil then
        RealisticLoadsWindLoss.initSpecFields(vehicle, spec);
    end

    -- Debug info
    if RealisticLoads.DEBUG_MODE then
        spec.debugInfo = {};
        spec.debugInfo.vehicleWorldRotationX = 0;
        spec.debugInfo.vehicleWorldRotationY = 0;
        spec.debugInfo.vehicleWorldRotationZ = 0;
    end

    spec.modInitialized = true;
end

-- Get vehicle velocity
function RealisticLoads:getVehicleVelocity()
    local spec = self.spec_realisticLoads;
    if not spec.modInitialized then
        return 0;
    end
    local velocity = self:getLastSpeed();
    return velocity or 0;
end

-- On load (called when vehicle is loaded)
function RealisticLoads:onLoad(savegame)
    print("[RealisticLoads]: onLoad CALLED for vehicle: " .. tostring(Vehicle.getFullName(self)));
    print("[RealisticLoads]: onLoad - vehicle type: " .. tostring(self.typeName or "UNKNOWN"));
    -- Initialize the mod on this vehicle
    if RealisticLoads.DEBUG_MODE then
        local vehicleName = "UNKNOWN";
        if Vehicle ~= nil and Vehicle.getFullName ~= nil then
            vehicleName = Vehicle.getFullName(self) or "UNKNOWN";
        end
        print(string.format("[RealisticLoads]: onLoad called for vehicle: %s", vehicleName));
    end
    RealisticLoads.initModOnVehicle(self);
end

-- On load finished (called after all vehicles are loaded)
function RealisticLoads:onLoadFinished(savegame)
    -- Ensure initialization completed
    local spec = self.spec_realisticLoads;
    if spec ~= nil and not spec.modInitialized then
        RealisticLoads.initModOnVehicle(self);
    end
end

-- On delete
function RealisticLoads:onDelete()
    local spec = self.spec_realisticLoads;
    if spec == nil then
        return;
    end

    -- Call wind loss cleanup (if module exists)
    if RealisticLoadsWindLoss ~= nil and RealisticLoadsWindLoss.onDelete ~= nil then
        RealisticLoadsWindLoss.onDelete(self, spec);
    end

    -- Call tilt loss cleanup (if module exists)
    if RealisticLoadsTiltLoss ~= nil and RealisticLoadsTiltLoss.onDelete ~= nil then
        RealisticLoadsTiltLoss.onDelete(self, spec);
    end
end

-- On update
function RealisticLoads:onUpdate(dt, isActiveForInput, isActiveForInputIngnoreSelection, isSelected)
    local spec = self.spec_realisticLoads;

    -- Safety checks
    if spec == nil then
        if RealisticLoads.DEBUG_MODE then
            print("[RealisticLoads]: onUpdate called but spec is nil");
        end
        return;
    end

    -- Ensure initialization happened
    if not spec.modInitialized then
        if RealisticLoads.DEBUG_MODE then
            local vehicleName = "UNKNOWN";
            if Vehicle ~= nil and Vehicle.getFullName ~= nil then
                vehicleName = Vehicle.getFullName(self) or "UNKNOWN";
            end
            print(string.format("[RealisticLoads]: onUpdate called but vehicle %s not initialized yet, initializing now...", vehicleName));
        end
        RealisticLoads.initModOnVehicle(self);
        if not spec.modInitialized then
            return; -- Still not initialized
        end
    end

    -- Ensure mod config is done before processing
    if not RealisticLoads.modConfigDone then
        RealisticLoads.initModData();
        if not RealisticLoads.modConfigDone then
            return; -- Still not ready, skip this update
        end
    end

    -- Performance check: Should we process this vehicle?
    if RealisticLoadsCommon ~= nil then
        if not RealisticLoadsCommon.shouldProcessVehicle(self, spec, dt, isActiveForInput) then
            -- If not active or no material, ensure particles are stopped
            if RealisticLoads.ENABLE_WIND_LOSS and RealisticLoadsWindLoss ~= nil then
                RealisticLoadsWindLoss.stopAllSmokeEmitters(spec);
            end
            return;
        end
    end

    -- Update vehicle speed
    spec.lastVehicleSpeed = RealisticLoads.getVehicleVelocity(self);
    
    -- Call wind loss update (if module exists)
    if RealisticLoads.ENABLE_WIND_LOSS and RealisticLoadsWindLoss ~= nil and RealisticLoadsWindLoss.affectFillUnits ~= nil then
        RealisticLoadsWindLoss.affectFillUnits(self, spec, dt);
    end
    
    -- Call tilt loss update (if module exists)
    if RealisticLoads.ENABLE_TILT_LOSS and RealisticLoadsTiltLoss ~= nil and RealisticLoadsTiltLoss.affectFillUnits ~= nil then
        RealisticLoadsTiltLoss.affectFillUnits(self, spec, dt);
    end
end

-- On draw (debug only)
function RealisticLoads:onDraw()
    local spec = self.spec_realisticLoads;

    if not spec.modInitialized or not RealisticLoads.DEBUG_MODE or not spec.vehicleSupported then
        return;
    end

    if g_currentMission.controlledVehicle ~= nil then
        local hudLineLevel = RealisticLoads.hudData.hudTextPosY;
        setTextColor(0, 1, 0, 1);
        setTextAlignment(RenderText.ALIGN_RIGHT);
        setTextVerticalAlignment(RenderText.VERTICAL_ALIGN_TOP);
        setTextBold(true);

        if RealisticLoads.ENABLE_TILT_LOSS and spec.debugInfo then
            local hudText = string.format("Tilt: rX:%.2f rY:%.2f rZ:%.2f gamma:%.1f° remVol:%.3f",
                    spec.debugInfo.vehicleWorldRotationX or 0,
                    spec.debugInfo.vehicleWorldRotationY or 0,
                    spec.debugInfo.vehicleWorldRotationZ or 0,
                    math.deg(spec.debugInfo.gamma or 0),
                    spec.debugInfo.remainingVol or 0
            );
            renderText(RealisticLoads.hudData.hudTextPosX, hudLineLevel, RealisticLoads.hudData.hudTextSize, hudText);
            hudLineLevel = hudLineLevel - RealisticLoads.hudData.hudTextSize * 1.1;
        end

        if RealisticLoads.ENABLE_WIND_LOSS then
            local hudText = string.format("Wind: v=%.1f km/h airSpeed=%.2f km/h",
                    spec.lastVehicleSpeed or 0,
                    spec.lastAirSpeed or 0
            );
            renderText(RealisticLoads.hudData.hudTextPosX, hudLineLevel, RealisticLoads.hudData.hudTextSize, hudText);
            hudLineLevel = hudLineLevel - RealisticLoads.hudData.hudTextSize * 1.1;
        end

        local specFillUnit = self.spec_fillUnit;
        for fillUnitIndex, fillUnit in pairs(spec.supportedFillUnits) do
            local fillType = specFillUnit:getFillUnitFillType(fillUnitIndex);
            local fillTypeProps = fillType ~= nil and RealisticLoadsCommon.getFillTypeProperties(fillType) or nil;

            hudLineLevel = hudLineLevel - RealisticLoads.hudData.hudTextSize * 1.1;
            local hudText = string.format("FillUnit[%d]: %.2f L",
                    fillUnitIndex,
                    fillUnit.fillLevel or 0
            );

            if fillTypeProps then
                hudText = hudText .. string.format(" [%s]", fillTypeProps.name);
            end

            if RealisticLoads.ENABLE_WIND_LOSS and spec.blowRatePerFillUnit then
                hudText = hudText .. string.format(" blowRate:%.4f", spec.blowRatePerFillUnit[fillUnitIndex] or 0);
            end

            renderText(RealisticLoads.hudData.hudTextPosX, hudLineLevel, RealisticLoads.hudData.hudTextSize, hudText);

            -- Show fill type properties in debug mode
            if fillTypeProps then
                hudLineLevel = hudLineLevel - RealisticLoads.hudData.hudTextSize * 1.1;
                local propsText = string.format("  Props: mass=%.4f kg/L firm=%.2f visc=%.2f",
                        fillTypeProps.massPerLiter,
                        fillTypeProps.firmness,
                        fillTypeProps.viscosity
                );
                renderText(RealisticLoads.hudData.hudTextPosX, hudLineLevel, RealisticLoads.hudData.hudTextSize, propsText);
            end
        end

        setTextColor(1, 1, 1, 1);
        setTextAlignment(RenderText.ALIGN_LEFT);
        setTextVerticalAlignment(RenderText.VERTICAL_ALIGN_BASELINE);
        setTextBold(false);
    end
end

print("[RealisticLoads]: Main file loaded successfully");

