--[[
    REALISTIC LOADS MOD - REGISTRATION
    =============================================================
    FS25 Style: Manual registration via loader file
]]

-- Print at the very top to verify file loads
print("[RealisticLoads]: REGISTRATION FILE - LINE 1");
print("[RealisticLoads]: ========================================");
print("[RealisticLoads]: Registration file loading...");
print("[RealisticLoads]: ========================================");

local modDirectory = g_currentModDirectory;
local modName = g_currentModName;

print(string.format("[RealisticLoads]: Mod: %s, Directory: %s", modName or "UNKNOWN", modDirectory or "UNKNOWN"));

-- Use pcall to catch any errors in the registration process
local success, error = pcall(function()

    -- Safety check: ensure specialization manager is available
    if g_specializationManager == nil then
        print("[RealisticLoads]: ERROR - g_specializationManager is nil! Cannot register specialization.");
        print("[RealisticLoads]: Will retry when managers are ready...");
        -- Don't return - continue to set up hooks that will work later
    end

    -- Add specialization manually
    if g_specializationManager ~= nil then
        print("[RealisticLoads]: Adding specialization to specialization manager...");
        g_specializationManager:addSpecialization('realisticLoads', 'RealisticLoads', Utils.getFilename('src/RealisticLoads.lua', modDirectory), "");
        print("[RealisticLoads]: Specialization added successfully");
    else
        print("[RealisticLoads]: WARNING - g_specializationManager is nil, specialization will be added later");
    end

    -- Hook into FillTypeManager.loadMapData to detect fill types AFTER they're loaded
    local fillTypeHookSet = false;
    local function setupFillTypeHook()
        if not fillTypeHookSet and FillTypeManager ~= nil and FillTypeManager.loadMapData ~= nil then
            FillTypeManager.loadMapData = Utils.appendedFunction(FillTypeManager.loadMapData, function(fillTypeManager, ...)
                -- Fill types are now loaded, find applicable ones
                if RealisticLoadsCommon ~= nil and not RealisticLoads.fillTypesDetected then
                    print("[RealisticLoads]: Fill types loaded, detecting applicable fill types...");
                    RealisticLoadsCommon.findApplicableFillTypes();
                    local fillTypeCount = 0;
                    for _ in pairs(RealisticLoads.applicableFillTypes) do
                        fillTypeCount = fillTypeCount + 1;
                    end
                    print(string.format("[RealisticLoads]: Found %d applicable fill types", fillTypeCount));
                    RealisticLoads.fillTypesDetected = true;
                    RealisticLoads.modConfigDone = true;
                    print("[RealisticLoads]: Mod configuration complete");
                end
            end);
            fillTypeHookSet = true;
            print("[RealisticLoads]: Hooked into FillTypeManager.loadMapData");
            return true;
        end
        return false;
    end

    -- Try to hook immediately
    setupFillTypeHook();

    -- Register to applicable vehicle types and set up fill type hook
    -- Hook into TypeManager.validateTypes to register when vehicle types are validated
    if TypeManager ~= nil then
        print("[RealisticLoads]: Setting up TypeManager.validateTypes hook...");
        TypeManager.validateTypes = Utils.appendedFunction(TypeManager.validateTypes, function(self)
            print("[RealisticLoads]: TypeManager.validateTypes hook called for type: " .. tostring(self.typeName or "UNKNOWN"));

            -- Try to set up FillTypeManager hook if not already set up
            if not fillTypeHookSet then
                setupFillTypeHook();
            end

            if self.typeName == "vehicle" then
                -- Wait for vehicle types to be ready
                if g_vehicleTypeManager ~= nil and g_vehicleTypeManager.types ~= nil then
                    for vehicleTypeName, vehicleType in pairs(g_vehicleTypeManager.types) do
                        if vehicleType ~= nil and vehicleType.specializations ~= nil then
                            -- Check prerequisites (FillUnit, FillVolume, Dischargeable, Wheels)
                            local hasFillUnit = SpecializationUtil.hasSpecialization(FillUnit, vehicleType.specializations);
                            local hasFillVolume = SpecializationUtil.hasSpecialization(FillVolume, vehicleType.specializations);
                            local hasDischargeable = SpecializationUtil.hasSpecialization(Dischargeable, vehicleType.specializations);
                            local hasWheels = SpecializationUtil.hasSpecialization(Wheels, vehicleType.specializations);

                            if hasFillUnit and hasFillVolume and hasDischargeable and hasWheels then
                                -- Check if vehicle should be blocked
                                local blocked = false;
                                if SpecializationUtil.hasSpecialization(Baler, vehicleType.specializations) then
                                    blocked = true;
                                end
                                if SpecializationUtil.hasSpecialization(ConveyorBelt, vehicleType.specializations) then
                                    blocked = true;
                                end

                                -- Check if already registered
                                if not blocked and not SpecializationUtil.hasSpecialization(RealisticLoads, vehicleType.specializations) then
                                    g_vehicleTypeManager:addSpecialization(vehicleTypeName, modName .. ".realisticLoads");
                                    print(string.format("[RealisticLoads]: Registered to vehicle type: %s", vehicleTypeName));
                                end
                            end
                        end
                    end
                    print("[RealisticLoads]: Vehicle type registration complete");
                end
            end
        end);
        print("[RealisticLoads]: TypeManager.validateTypes hook set up");

        -- Also try to add specialization when managers become available (within same hook)
        TypeManager.validateTypes = Utils.appendedFunction(TypeManager.validateTypes, function(self)
            if g_specializationManager ~= nil then
                local specializationAdded = g_specializationManager:getSpecializationObjectByName(modName .. ".realisticLoads");
                if specializationAdded == nil then
                    print("[RealisticLoads]: Adding specialization to specialization manager (delayed)...");
                    g_specializationManager:addSpecialization('realisticLoads', 'RealisticLoads', Utils.getFilename('src/RealisticLoads.lua', modDirectory), "");
                    print("[RealisticLoads]: Specialization added successfully (delayed)");
                end
            end
        end);
    else
        print("[RealisticLoads]: WARNING - TypeManager is nil, hooks will be set up later");
    end

    print("[RealisticLoads]: Registration setup complete");
end);  -- End pcall

if not success then
    printError(string.format("[RealisticLoads]: ERROR in registration file: %s", tostring(error)));
    printError("[RealisticLoads]: Registration file failed to load completely");
    -- Still try to add specialization if possible
    if g_specializationManager ~= nil then
        local specializationAdded = g_specializationManager:getSpecializationObjectByName(modName .. ".realisticLoads");
        if specializationAdded == nil then
            print("[RealisticLoads]: Attempting to add specialization despite error...");
            g_specializationManager:addSpecialization('realisticLoads', 'RealisticLoads', Utils.getFilename('src/RealisticLoads.lua', modDirectory), "");
        end
    end
else
    print("[RealisticLoads]: Registration file loaded successfully");
end

