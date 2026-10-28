Config = {}

Config.Debug = true

Config.ServerName = 'Monoskrypt RP'

Config.MinCharacterSlot = 1
Config.MaxCharacterSlots = 3

Config.Spawn = {}

Config.Spawn.Default = {
    x = -1037.0,
    y = -2737.85,
    z = 20.17,
    heading = 330.0
}

Config.Spawn.FadeOutTime = 500
Config.Spawn.FadeInTime = 1000

Config.Spawn.CollisionTimeout = 10000
Config.Spawn.ModelTimeout = 10000

Config.Spawn.RestoreLastPosition = false

Config.PlayerIds = {
    Enabled = true,
    Key = 'Z',
    Distance = 25.0,
    HeadOffset = 0.28,
    RequireLineOfSight = true
}

Config.StockPolice = {}

Config.StockPolice.Remove = true

Config.StockPolice.CleanupInterval = 1500

Config.StockPolice.DispatchServices = { 1, 2, 4, 6, 7, 8, 9, 10, 12, 13, 14 }

Config.StockPolice.Vehicles = {
    'police', 'police2', 'police3', 'police4', 'policeb', 'policet', 'polmav',
    'sheriff', 'sheriff2', 'riot', 'riot2', 'fbi', 'fbi2', 'pranger', 'predator'
}

Config.StockPolice.Peds = {
    's_m_y_cop_01', 's_f_y_cop_01', 's_m_y_sheriff_01', 's_f_y_sheriff_01',
    's_m_y_hwaycop_01', 's_m_y_swat_01', 's_m_y_ranger_01', 's_f_y_ranger_01',
    's_m_m_snowcop_01'
}

Config.StockPolice.Scenarios = {
    'WORLD_HUMAN_COP_IDLES', 'WORLD_VEHICLE_POLICE_CAR',
    'WORLD_VEHICLE_POLICE_BIKE', 'WORLD_VEHICLE_POLICE_NEXT_TO_CAR'
}

Config.Zancudo = {}

Config.Zancudo.Remove = true

Config.Zancudo.Area = { minX = -2750.0, maxX = -1600.0, minY = 2800.0, maxY = 3500.0 }

Config.Zancudo.CleanupInterval = 1500

Config.Zancudo.Vehicles = {
    'buzzard', 'buzzard2', 'barracks', 'barracks2', 'barracks3', 'rhino', 'crusader',
    'insurgent', 'insurgent2', 'insurgent3', 'apc', 'lazer', 'hydra', 'valkyrie', 'valkyrie2',
    'savage', 'cargobob', 'cargobob2', 'cargobob3', 'cargobob4', 'khanjali', 'halftrack',
    'titan', 'besra', 'molotok', 'tula', 'bombushka', 'starling'
}

Config.Zancudo.Peds = {
    's_m_y_marine_01', 's_m_y_marine_02', 's_m_y_marine_03', 's_m_m_marine_01', 's_m_m_marine_02',
    's_m_y_armymech_01', 's_m_y_blackops_01', 's_m_y_blackops_02', 's_m_y_blackops_03'
}

Config.Zancudo.Scenarios = {
    'WORLD_HUMAN_GUARD_STAND_ARMY', 'WORLD_HUMAN_GUARD_PATROL',
    'WORLD_VEHICLE_MILITARY_PLANES_BIG', 'WORLD_VEHICLE_MILITARY_PLANES_SMALL'
}

Config.Zancudo.ScenarioGroups = { 'ARMY_GUARD', 'ARMY_HELI' }
