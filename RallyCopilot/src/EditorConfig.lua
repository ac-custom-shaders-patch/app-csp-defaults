local turnLut = ac.DataLUT11.parse('7=6|10=5|16=4|30=3|50=2|80=1')
turnLut.useCubicInterpolation = true
turnLut.extrapolate = false

local jumpLut = ac.DataLUT11.parse('5=0|6.5=1|10=2|12=3|15=3.5')
jumpLut.useCubicInterpolation = true
jumpLut.extrapolate = false

return {
    -- Когда всё будет готово, можно будет поменять на `false`, чтобы было немного быстрее
    DebugMode = false,

    -- Размер одного шага
    StepSize = 4,

    -- Множитель для сглаживания сплайна
    SmoothingMult = 1,

    -- Условия для сброса собранного поворота
    Nullification = {
        Angle = 5,     -- если максимально встреченный угол меньше...
        Distance = 250  -- и расстояние больше...
                       -- ...забываем про этот поворот
    },

    -- Условия для завершения собранного поворота
    EndingConditions = {
        AngleFallingBelow = 0.3,  -- если угол меньше 15% от максимально встреченного угла...
        CounterThreshold = 3       -- и таких точек увидели как минимум две...
                                   -- ...завершаем накопление поворота
    },

    -- Условия, чтобы собранный поворот считался за реальный
    CornerRequirements = {
        MaxStepAngleAbove = 1,        -- если максимально встреченный угол больше...
        AngleToDistanceRatio = 0.3,  -- (и отношение угла к расстоянию поворота больше...
        OrAngleAbove = 8              -- или общий угол поворота больше)...
                                      -- ...то это поворот
    },

    -- Обрезание поворота спереди и сзади (выкидываем точки с небольшими углами)
    TrimmingAngles = {
        Beginning = 1,  -- спереди
        Ending = 1      -- сзади
    },

    -- Параметры для схлопывания поворотов
    Merge = {
        DistanceToPreviousCornerBelow = 10,  -- если до предыдущего найденного поворота меньше...
        PreviousCornerDistanceBelow = 25,    -- и его расстояние меньше...
        OwnDifficultyThreshold = 6,          -- и сложность нового поворота ниже...
        PreviousDifficultyThreshold = 1,     -- и сложность предыдущего выше...
        UniteInsteadOfDropping = true        -- ...удаляем предыдущий поворот, или слепляем оба вместе, если тут `true`
    },

    -- Параметры для уточнений поворотов
    Hints = {
        LongDistanceThreshold = 100,      -- порог для длинного
        VeryLongDistanceThreshold = 200,  -- порог для очень длинного
        TightensAnglesRatio = 1.5,        -- порог для аттрибута tightens
    },

    -- Минимальное расстояние, с которого добавлять прямые
    MinDistanceForStraight = 50,

    -- Апекс посередине (а не там, где угол наибольший)
    SnapCenterToMiddle = true,

    -- Функция, высчитывающая сложность поворота от 1 до 6 (на вход получает угол в градусах, расстояние в метрах и аппроксимированную скорость)
    DifficultyComputation = function (angle, distance, speedKmh)
        local lengthMult = (40 - distance) * 0.2
        local turnValue = math.round(turnLut:get(math.abs(angle) + lengthMult))
        return turnValue
    end,

    -- Функция, высчитывающая тип прыжка: 1 для большого, 3 для overcrest (если не вернуть ничего, 0 или false, прыжка не будет)
    JumpComputation = function (angle, distance, speedKmh)
        local jumpValue = jumpLut:get(angle) + (speedKmh - 110) / 100
        jumpValue = jumpValue > 2.2 and jumpValue + (distance - 100) / 100 or jumpValue - (distance - 50) / 100
        jumpValue = distance < 10 and 0 or jumpValue
        jumpValue = speedKmh < 90 and jumpValue + (speedKmh - 90) / 50 or jumpValue
        jumpValue = math.clamp(math.round(jumpValue), 0, 3)
        jumpValue = jumpValue > 0 and 4 - jumpValue or jumpValue
        return jumpValue
    end
}