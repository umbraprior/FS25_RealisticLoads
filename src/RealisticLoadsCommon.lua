--[[
    REALISTIC LOADS MOD - COMMON UTILITIES
    =============================================================
    Shared functions and utilities used by both wind and tilt loss systems
]]

print("[RealisticLoads]: Common utilities file loading...");

-- Ensure RealisticLoads namespace exists
if RealisticLoads == nil then
    RealisticLoads = {};
end

-- Create Common namespace
RealisticLoadsCommon = {};

--[[
    PERFORMANCE / LIMITATION FUNCTIONS
]]

-- Check if vehicle is active (should be processed)
-- Returns true if vehicle is AI-controlled, player-controlled, or within activation distance
function RealisticLoadsCommon.isVehicleActive(vehicle, isActiveForInput)
    if vehicle == nil then
        return false;
    end
    
    -- Check if vehicle is AI-controlled (AI workers should always be processed)
    if vehicle.getIsAIActive ~= nil and vehicle:getIsAIActive() then
        return true; -- AI workers are always active
    end
    
    -- Check if vehicle is controlled by player (active for input)
    if isActiveForInput then
        return true;
    end
    
    -- Check distance to players (only if not AI or player-controlled)
    local maxDistance = 250; -- meters
    if g_currentMission.player ~= nil then
        local distance = calcDistanceFrom(g_currentMission.player.rootNode, vehicle.rootNode);
        if distance <= maxDistance then
            return true;
        end
    end
    
    -- Check all players (for multiplayer)
    if g_currentMission.players ~= nil then
        for _, player in pairs(g_currentMission.players) do
            if player ~= nil and player.rootNode ~= nil then
                local distance = calcDistanceFrom(player.rootNode, vehicle.rootNode);
                if distance <= maxDistance then
                    return true;
                end
            end
        end
    end
    
    return false; -- Not within activation distance
end

-- Check if vehicle should be processed (combines all early exit checks)
function RealisticLoadsCommon.shouldProcessVehicle(vehicle, spec, dt, isActiveForInput)
    if vehicle == nil or spec == nil then
        return false;
    end
    
    -- Check if vehicle is supported
    if not spec.modInitialized or not spec.vehicleSupported then
        return false;
    end
    
    -- 1. Distance-based activation (with AI support)
    if not RealisticLoadsCommon.isVehicleActive(vehicle, isActiveForInput) then
        return false;
    end
    
    -- 2. Fill level early exit
    if not RealisticLoadsCommon.hasAnyMaterial(vehicle, spec) then
        return false;
    end
    
    -- 3. Check if we have any supported fill units
    if spec.supportedFillUnits == nil or next(spec.supportedFillUnits) == nil then
        return false;
    end
    
    return true;
end

-- Check if vehicle has any material (early exit for empty vehicles)
function RealisticLoadsCommon.hasAnyMaterial(vehicle, spec)
    if vehicle == nil or spec == nil then
        return false;
    end
    
    local specFillUnit = vehicle.spec_fillUnit;
    if specFillUnit == nil or spec.supportedFillUnits == nil then
        return false;
    end
    
    for fillUnitIndex, _ in pairs(spec.supportedFillUnits) do
        local fillLevel = specFillUnit:getFillUnitFillLevelPercentage(fillUnitIndex);
        if fillLevel and fillLevel > 0.01 then
            return true;
        end
    end
    
    return false;
end

--[[
    VEHICLE SUPPORT FUNCTIONS
]]

-- Check if vehicle is supported by RealisticLoads
function RealisticLoadsCommon.getVehicleIsSupportedByRealisticLoads(vehicle)
    -- Safety check: ensure mod data is initialized
    if not RealisticLoads.modConfigDone then
        return false, {};
    end

    local spec = vehicle.spec_realisticLoads;
    local specFillUnit = vehicle.spec_fillUnit;
    local vehicleSupported = false;

    -- Check if excluded
    local vehicleName = nil;
    if Vehicle ~= nil and Vehicle.getFullName ~= nil then
        vehicleName = Vehicle.getFullName(vehicle);
    end
    if vehicleName ~= nil then
        vehicleName = vehicleName:upper();
        if RealisticLoads.vehicleTypesToExclude ~= nil and RealisticLoads.vehicleTypesToExclude[vehicleName] == true then
            return false, {};
        end
    end

    -- Check prerequisites
    if specFillUnit == nil then
        return false, {};
    end

    local fillUnits = nil;
    if specFillUnit.getFillUnits ~= nil then
        fillUnits = specFillUnit:getFillUnits();
    end
    if fillUnits == nil or not (#fillUnits > 0) then
        return false, {};
    end

    -- Find supported fill units - supports all fill types EXCEPT liquids/slurry
    local supportedFillUnits = {};
    for fillUnitIndex, fillUnit in pairs(fillUnits) do
        local supportedFillTypes = nil;
        if specFillUnit.getFillUnitSupportedFillTypes ~= nil then
            supportedFillTypes = specFillUnit:getFillUnitSupportedFillTypes(fillUnitIndex);
        end
        if supportedFillTypes ~= nil and next(supportedFillTypes) ~= nil then
            -- Check if any fill type in this unit is a liquid/slurry exclude if so
            local shouldExclude = false;
            if g_fillTypeManager ~= nil then
                for fillTypeIndex, _ in pairs(supportedFillTypes) do
                    -- Exclude liquid and slurry fill types
                    if g_fillTypeManager.getIsFillTypeInCategory ~= nil then
                        if g_fillTypeManager:getIsFillTypeInCategory(fillTypeIndex, "LIQUID") or
                                g_fillTypeManager:getIsFillTypeInCategory(fillTypeIndex, "SLURRYTANK") then
                            shouldExclude = true;
                            break;
                        end
                    end
                end
            end
            if not shouldExclude then
                supportedFillUnits[fillUnitIndex] = fillUnit;
                vehicleSupported = true;
            end
        end
    end

    return vehicleSupported, supportedFillUnits;
end

--[[
    COVER / EXPOSURE FUNCTIONS
]]

-- Get cover for a specific fill unit (helper function)
function RealisticLoadsCommon.getCoverByFillUnitIndex(vehicle, fillUnitIndex)
    if vehicle.spec_cover == nil then
        return nil;
    end
    
    -- Check if vehicle has getCoverByFillUnitIndex function
    if vehicle.getCoverByFillUnitIndex ~= nil then
        return vehicle:getCoverByFillUnitIndex(fillUnitIndex);
    end
    
    return nil;
end

-- Check if fill unit is exposed (cover open or no cover, vehicle unfolded)
function RealisticLoadsCommon.isFillUnitExposed(vehicle, fillUnitIndex)
    -- Check if vehicle is unfolded (for combines, sprayers, etc.)
    local isUnfolded = true;
    if vehicle.spec_foldable ~= nil and vehicle.getIsUnfolded ~= nil then
        isUnfolded = vehicle:getIsUnfolded();
    end
    if not isUnfolded then
        return false; -- Folded, not exposed
    end

    -- Check cover state - cover must be OPEN (state > 0) for losses
    if vehicle.spec_cover ~= nil then
        local specCover = vehicle.spec_cover;
        local cover = RealisticLoadsCommon.getCoverByFillUnitIndex(vehicle, fillUnitIndex);
        if cover ~= nil then
            -- Cover exists - it's exposed only if state > 0 (open)
            -- Cover state 0 = closed, state > 0 = open
            return (specCover.state > 0);
        else
            -- No cover for this fill unit, so it's exposed
            return true;
        end
    else
        -- No cover specialization - vehicle is open (e.g., working vehicles, open trailers)
        return true;
    end
end

--[[
    FILL TYPE UTILITIES
]]

-- Find applicable fill types
function RealisticLoadsCommon.findApplicableFillTypes()
    -- Safety check: ensure manager is available
    if g_fillTypeManager == nil then
        print("[RealisticLoads]: ERROR - g_fillTypeManager is nil in findApplicableFillTypes");
        return;
    end

    -- getFillTypes() returns self.fillTypes which is an array (indexed from 1)
    local fillTypesArray = g_fillTypeManager:getFillTypes();
    if fillTypesArray == nil then
        print("[RealisticLoads]: ERROR - getFillTypes() returned nil");
        return;
    end

    print(string.format("[RealisticLoads]: getFillTypes() returned %d fill types", #fillTypesArray));

    -- Iterate through the array (indexed from 1, not 0)
    local fillTypeCount = 0;
    for i = 1, #fillTypesArray do
        local fillType = fillTypesArray[i];
        if fillType ~= nil and fillType.name ~= nil then
            RealisticLoads.applicableFillTypes[fillType.name] = fillType;
            RealisticLoads.fillTypesIndexToName[fillType.index] = fillType.name;
            fillTypeCount = fillTypeCount + 1;
            if RealisticLoads.DEBUG_MODE and fillTypeCount <= 10 then
                print(string.format("[RealisticLoads]: Found fill type: %s (index: %d)", fillType.name, fillType.index));
            end
        end
    end

    print(string.format("[RealisticLoads]: Total applicable fill types: %d", fillTypeCount));
end

-- Get fill type properties (mass, firmness, viscosity, etc.)
function RealisticLoadsCommon.getFillTypeProperties(fillTypeIndex)
    -- Safety check
    if g_fillTypeManager == nil or fillTypeIndex == nil then
        return {
            massPerLiter = RealisticLoads.STANDARD_MASS_PER_LITER,
            maxPhysicalSurfaceAngle = math.rad(30),
            firmness = 0.5,
            viscosity = 0.5,
            name = "UNKNOWN"
        };
    end

    local fillTypeData = g_fillTypeManager:getFillTypeByIndex(fillTypeIndex);
    if fillTypeData == nil then
        return {
            massPerLiter = RealisticLoads.STANDARD_MASS_PER_LITER,
            maxPhysicalSurfaceAngle = math.rad(30),
            firmness = 0.5,
            viscosity = 0.5,
            name = "UNKNOWN"
        };
    end

    -- Extract properties including nested layerParameters
    local layerParams = fillTypeData.layerParameters or {};

    return {
        massPerLiter = fillTypeData.massPerLiter or RealisticLoads.STANDARD_MASS_PER_LITER,
        maxPhysicalSurfaceAngle = fillTypeData.maxPhysicalSurfaceAngle or math.rad(30),
        firmness = layerParams.firmness or 0.5,
        viscosity = layerParams.viscosity or 0.5,
        name = fillTypeData.name or "UNKNOWN"
    };
end

--[[
    SPEC FIELD INITIALIZATION HELPERS
]]

-- Initialize shared spec fields
function RealisticLoadsCommon.initSpecFields(vehicle, spec)
    if vehicle == nil or spec == nil then
        return;
    end
    
    -- Initialize basic fields
    spec.lastVehicleSpeed = 0;
    spec.supportedFillUnits = {};
    spec.vehicle = vehicle;
    
    -- Check if vehicle is supported
    local vehicleSupported, supportedFillUnits = RealisticLoadsCommon.getVehicleIsSupportedByRealisticLoads(vehicle);
    spec.vehicleSupported = vehicleSupported or false;
    spec.supportedFillUnits = supportedFillUnits or {};
    
    -- Debug info
    if RealisticLoads.DEBUG_MODE then
        local vehicleName = "UNKNOWN";
        if Vehicle ~= nil and Vehicle.getFullName ~= nil then
            vehicleName = Vehicle.getFullName(vehicle) or "UNKNOWN";
        end
        print(string.format("[RealisticLoads]: Initialized for vehicle %s - Supported: %s, FillUnits: %d",
                vehicleName, tostring(spec.vehicleSupported), table.maxn(spec.supportedFillUnits) or 0));
    end
end

print("[RealisticLoads]: Common utilities file loaded successfully");

