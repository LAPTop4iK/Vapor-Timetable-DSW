//
//  MockFactory.swift
//  DswAggregator
//
//  Created by Mikita Laptsionak on 27/10/2025.
//


import Foundation
import Vapor

enum MockFactory {

    // ===== Настройки плотности =====
    private static let GROUP_PAIRS_PER_DAY_RANGE = 1...3//4...6      // пары в день для группы
    private static let TEACHER_EVENTS_TARGET_RANGE = 40...50//80...200  // ЦЕЛЬ на препода за семестр
    private static let PICK_MOD_BASE = 3                       // чем больше — тем реже пары у препода

    // ===== Справочники =====
    // Расширил до 24 нейтральных преподавателей
    static let teacherSeeds: [(id: Int, name: String, title: String, dept: String, email: String, phone: String)] = [
        (100, "John Smith",    "PhD", "Computer Science", "[email protected]", "+48 500 001 001"),
        (101, "Maria Nowak",   "MSc", "Mathematics",      "[email protected]", "+48 500 001 002"),
        (102, "Adam Johnson",  "Dr.",  "Economics",       "[email protected]", "+48 500 001 003"),
        (103, "Anna Kowalska", "PhD", "Psychology",       "[email protected]", "+48 500 001 004"),
        (104, "Peter Brown",   "MSc", "Design",           "[email protected]", "+48 500 001 005"),
        (105, "Emily Davis",   "Dr.",  "Linguistics",     "[email protected]", "+48 500 001 006"),
        (106, "Liam Wilson",   "PhD", "Data Science",     "[email protected]", "+48 500 001 007"),
        (107, "Olivia Garcia", "MSc", "Management",       "[email protected]", "+48 500 001 008"),
        (108, "Jacob Miller",  "PhD", "Machine Learning", "[email protected]", "+48 500 001 009"),
        (109, "Sophie Martin", "MSc", "Statistics",       "[email protected]", "+48 500 001 010"),
        (110, "Noah Thompson", "Dr.",  "Finance",         "[email protected]", "+48 500 001 011"),
//        (111, "Ava Hernandez", "PhD", "Marketing",        "[email protected]", "+48 500 001 012"),
//        (112, "Marek Zielinski","MSc","Informatics",      "[email protected]", "+48 500 001 013"),
//        (113, "Ewa Kaczmarek", "Dr.", "Sociology",        "[email protected]", "+48 500 001 014"),
//        (114, "Lucas White",   "PhD", "Networks",         "[email protected]", "+48 500 001 015"),
//        (115, "Chloe Lewis",   "MSc", "UX Design",        "[email protected]", "+48 500 001 016"),
//        (116, "Daniel Evans",  "Dr.",  "Physics",         "[email protected]", "+48 500 001 017"),
//        (117, "Mia Clark",     "PhD", "Biostatistics",    "[email protected]", "+48 500 001 018"),
//        (118, "Tomasz Wójcik", "MSc", "AI Systems",       "[email protected]", "+48 500 001 019"),
//        (119, "Julia Nowicka", "Dr.",  "HR Management",   "[email protected]", "+48 500 001 020"),
//        (120, "Ethan Baker",   "PhD", "Cybersecurity",    "[email protected]", "+48 500 001 021"),
//        (121, "Nina Adams",    "MSc", "Data Engineering", "[email protected]", "+48 500 001 022"),
//        (122, "Oscar Perez",   "Dr.",  "Operations",      "[email protected]", "+48 500 001 023"),
//        (123, "Sara Rossi",    "PhD", "Cognitive Sci.",   "[email protected]", "+48 500 001 024"),
    ]

    static let subjects = [
        "Introduction to Programming", "Linear Algebra", "Microeconomics",
        "Cognitive Psychology", "Visual Design Basics", "Academic Writing",
        "Data Analysis", "Project Management"
    ]
    static let rooms = ["A101","A202","B305","C410","Distance Learning","Remote Room","Lab-1","Seminar-2"]
    static let lessonTypes = ["Wyk","Cw","Labor","Sem","Proj"]
    static let gradings = ["Zaliczenie", "Egzamin", "Nie dotyczy"]
    static let tracks = ["Full-time", "Part-time", "Evening"]
    static let remarksList = ["", "Distance learning", "Zajęcia odwołane", "Sala na zajęcia zdalne"]

    static let timeSlots: [(String, String)] = [
        ("08:00","09:30"), ("09:45","11:15"), ("11:30","13:00"),
        ("13:45","15:15"), ("15:30","17:00"), ("17:15","18:45"), ("19:00","20:30")
    ]

    // ===== Форматтеры и даты семестра (как в прошлой версии) =====
    private static let tz = TimeZone(identifier: "Europe/Warsaw")!
    private static func iso(_ date: Date) -> String {
        let f = ISO8601DateFormatter(); f.timeZone = tz
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.string(from: date)
    }
    private static func date(_ yyyyMMdd: String, at hm: String) -> Date {
        let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd HH:mm"; df.timeZone = tz
        return df.date(from: "\(yyyyMMdd) \(hm)") ?? Date()
    }
    private static func dayString(_ d: Date) -> String {
        let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd"; df.timeZone = tz
        return df.string(from: d)
    }
    private static func semesterDays(from f: String?, to t: String?) -> [String] {
        let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd"; df.timeZone = tz
        let start = (f.flatMap { df.date(from: String($0.prefix(10))) }) ?? df.date(from: "2025-09-01")!
        let end   = (t.flatMap { df.date(from: String($0.prefix(10))) }) ?? df.date(from: "2026-02-10")!
        var cal = Calendar(identifier: .gregorian); cal.timeZone = tz
        var cur = start; var days: [String] = []
        while cur <= end {
            let wd = cal.component(.weekday, from: cur) // 1=Вс
            if (2...7).contains(wd) { days.append(dayString(cur)) } // Пн–Сб
            cur = cal.date(byAdding: .day, value: 1, to: cur)!
        }
        return days
    }

    // ===== Событие =====
    private static func makeEvent(day: String, slot: (String,String), subjectIx: Int,
                                  teacher: (id:Int, name:String), roomIx: Int, trackIx: Int,
                                  remarkIx: Int, gradingIx: Int, typeIx: Int, groups: String) -> ScheduleEvent {
        let start = date(day, at: slot.0), end = date(day, at: slot.1)
        return ScheduleEvent(
            title: subjects[subjectIx % subjects.count],
            teacherName: teacher.name, teacherId: teacher.id, teacherEmail: nil,
            room: rooms[roomIx % rooms.count], type: lessonTypes[typeIx % lessonTypes.count],
            grading: gradings[gradingIx % gradings.count], studyTrack: tracks[trackIx % tracks.count],
            groups: groups,
            remarks: { let r = remarksList[remarkIx % remarksList.count]; return r.isEmpty ? nil : r }(),
            startISO: iso(start), endISO: iso(end)
        )
    }

    // ===== Агрегат =====
    static func makeAggregate(groupId: Int, from: String?, to: String?, intervalType: IntervalType) -> AggregateResponse {
        let days = semesterDays(from: from, to: to)
        let groupTag = "sem-\(String(format: "%03d", groupId % 1000))"

        // --- Группа ---
        var groupSchedule: [ScheduleEvent] = []
        for (dIndex, day) in days.enumerated() {
            let pairsCount = Int.random(in: GROUP_PAIRS_PER_DAY_RANGE)
            for p in 0..<pairsCount {
                let tSeed = teacherSeeds[(dIndex + p) % teacherSeeds.count]
                let ev = makeEvent(
                    day: day,
                    slot: timeSlots[(p + dIndex) % timeSlots.count],
                    subjectIx: dIndex + p, teacher: (tSeed.id, tSeed.name),
                    roomIx: dIndex + p, trackIx: p,
                    remarkIx: (dIndex % 23 == 0 && p == 0) ? 2 : 0, // редкие отмены
                    gradingIx: p, typeIx: dIndex + p, groups: groupTag
                )
                groupSchedule.append(ev)
            }
        }

        // --- Преподаватели: целевое количество 80–200 на человека ---
        var teachers: [TeacherCard] = []
        // фиксируем RNG на основе id, чтобы ответы были стабильны между перезапусками
        for (idx, seed) in teacherSeeds.enumerated() {
            var rng = SeededRandom(seed: UInt64(seed.id * 1_000_003 + 17))
            let target = rng.int(in: TEACHER_EVENTS_TARGET_RANGE)       // 80..200

            var schedule: [ScheduleEvent] = []
            var counter = 0
            let pickMod = PICK_MOD_BASE + (idx % 2)                     // лёгкая вариативность частоты

            outer: while schedule.count < target {
                for (dIndex, day) in days.enumerated() {
                    for (sIndex, slot) in timeSlots.enumerated() {
                        let pick = ((dIndex + sIndex + idx) % pickMod) != 0
                        if !pick { continue }
                        let ev = makeEvent(
                            day: day, slot: slot,
                            subjectIx: idx + counter, teacher: (seed.id, seed.name),
                            roomIx: idx + counter, trackIx: idx + dIndex + sIndex,
                            remarkIx: (counter % 19 == 0) ? 1 : 0, // иногда дистанционно
                            gradingIx: idx + counter, typeIx: idx + counter, groups: groupTag
                        )
                        schedule.append(ev)
                        counter += 1
                        if schedule.count >= target { break outer }
                    }
                }
            }

            teachers.append(.init(
                id: seed.id, name: seed.name, title: seed.title, department: seed.dept,
                email: seed.email, phone: seed.phone,
                aboutHTML: "<p>\(seed.name) – \(seed.title) at \(seed.dept).</p>",
                schedule: schedule
            ))
        }

        let startStr = from ?? days.first ?? "2025-09-01"
        let endStr   = to   ?? days.last  ?? "2026-02-10"

        return AggregateResponse(
            groupId: groupId, from: startStr, to: endStr,
            intervalType: intervalType.rawValue,
            groupSchedule: groupSchedule, teachers: teachers,
            fetchedAt: ISO8601DateFormatter().string(from: Date())
        )
    }

    // ===== Список групп (без изменений) =====
    static func makeGroups() -> [GroupInfo] {
        let faculties = ["Faculty of Arts", "Faculty of IT", "Faculty of Business", "Faculty of Social Sciences"]
        let programs  = ["BA", "BSc", "MA", "MSc"]
        var out: [GroupInfo] = []
        for i in 0..<10 {
            let gid = 5000 + i
            let code = "SEM-\(100 + i)"
            let name = "Semester Group \(i+1)"
            let tr: [TrackInfo] = [
                TrackInfo(trackId: gid*10 + 1, title: tracks[(i+0)%tracks.count]),
                TrackInfo(trackId: gid*10 + 2, title: tracks[(i+1)%tracks.count])
            ]
            out.append(.init(groupId: gid, code: code, name: name, tracks: tr,
                             program: programs[i % programs.count],
                             faculty: faculties[(i*2) % faculties.count]))
        }
        return out.enumerated().map { idx, g in
            idx % 3 == 0 ? g : .init(groupId: g.groupId, code: g.code,
                                      name: g.name.replacingOccurrences(of: " ", with: "-"),
                                      tracks: g.tracks.shuffled(), program: g.program, faculty: g.faculty)
        }
    }

    static func featureFlags() -> FeatureFlagsResponse {
        .init(flags: [
            "show_subjects_tab": .bool(false), "show_teachers_tab": .bool(false),
            "enable_analytics": .bool(false), "show_ads": .bool(false),
            "enable_push_notifications": .bool(false), "dark_mode_only": .bool(false),
            "show_debug_menu": .bool(false), /*FeatureCases.premiumTrialDuration.rawValue: .int(60 * 60 * 24)*/
        ], version: "1.0(1)-mock", updatedAt: String(Int(Date().timeIntervalSince1970)))
    }

    static func featureParameters() -> FeatureParametersResponse {
        .init(parameters: [
        ParameterCases.premiumTrialDuration.rawValue: .int(60 * 60 * 24)
        ], version: "1.0(1)-mock", updatedAt: String(Int(Date().timeIntervalSince1970)))
    }

    static func makeGroupScheduleOnly(groupId: Int, from: String?, to: String?, intervalType: IntervalType) -> GroupScheduleResponse {
        // Переиспользуем логику генерации из makeAggregate, но берём только часть groupSchedule
        let agg = makeAggregate(groupId: groupId, from: from, to: to, intervalType: intervalType)
        return GroupScheduleResponse(
            groupId: agg.groupId,
            from: agg.from,
            to: agg.to,
            intervalType: agg.intervalType,
            groupSchedule: agg.groupSchedule,
            fetchedAt: agg.fetchedAt
        )
    }
}