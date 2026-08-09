import Foundation

/// Mirror of the web app's `lib/cuisine-data.ts`.
///
/// Keep these strings verbatim — the server compares cuisine and dish names
/// literally when computing AI suggestions, so a stray capital or a "and" turned
/// into "&" silently drops a user's preference on the floor.
public enum CuisineData {

    public struct CuisineDishes: Hashable, Sendable {
        public let breakfast: [String]
        public let lunchDinnerVeg: [String]
        public let lunchDinnerNonVeg: [String]
        public let snacks: [String]
    }

    public struct Cuisine: Hashable, Sendable, Identifiable {
        public let name: String
        public let dishes: CuisineDishes
        public var id: String { name }
    }

    /// Result of `dishesFor` — distinct strings per pool.
    public struct DishPool: Hashable, Sendable {
        public let breakfast: [String]
        public let lunchDinner: [String]
        public let snacks: [String]
    }

    public static let cuisines: [Cuisine] = [
        Cuisine(
            name: "Maharashtrian",
            dishes: CuisineDishes(
                breakfast: [
                    "Poha", "Sabudana Khichdi", "Thalipeeth", "Misal Pav", "Upma",
                    "Idli Sambaar", "Sandwich",
                ],
                lunchDinnerVeg: [
                    "Puran Poli", "Varan-Bhaat", "Zunka-Bhakar", "Bharli Vangi", "Pav Bhaji",
                ],
                lunchDinnerNonVeg: ["Kolhapuri Chicken", "Malvani Fish Curry"],
                snacks: ["Vada Pav", "Bhakarwadi", "Kothimbir Vadi"]
            )
        ),
        Cuisine(
            name: "North Indian",
            dishes: CuisineDishes(
                breakfast: [
                    "Aloo Puri", "Aloo Paratha", "Sattu Paratha", "Sabudana Khichdi",
                    "Dahi Chura", "Suji Halwa", "Besan Chilla", "Moong Dal Chilla",
                ],
                lunchDinnerVeg: [
                    "Chole Bhature", "Dal Baati, Churma", "Litti Chokha", "Dal Makhani",
                    "Palak Paneer", "Chana Masala", "Rajma", "Chhole", "Ker Sangri",
                    "Dum Aloo", "Vegetable Curry", "Paneer Bhurji",
                ],
                lunchDinnerNonVeg: [
                    "Butter Chicken", "Tandoori Chicken", "Rogan Josh", "Laal Maas",
                    "Chicken Curry", "Fish Curry",
                ],
                snacks: [
                    "Samosa", "Pakora", "Kachori", "Jalebi", "Gulab Jamun", "Rasgulla",
                    "Ghewar", "Mawa Kachori", "Kashmiri Samosa", "Nadru Monje",
                    "Kashmiri Tea", "Sheer Chai", "Singodi", "Bal Mithai", "Arsa",
                    "Jhangora Ki Kheer", "Patande", "Aktori", "Chaat",
                ]
            )
        ),
        Cuisine(
            name: "South Indian",
            dishes: CuisineDishes(
                breakfast: [
                    "Pongal", "Appam", "Puttu", "Idiyappam", "Rava Idli", "Rava Dosa",
                ],
                lunchDinnerVeg: [
                    "Sambar Rice", "Rasam Rice", "Coconut Rice", "Vegetable Curry",
                    "Sambar", "Rasam", "Bisi Bele Bath", "Ragi Mudde",
                ],
                lunchDinnerNonVeg: ["Fish Curry", "Chicken Curry", "Prawn Curry"],
                snacks: [
                    "Vada", "Bonda", "Bajji", "Murukku", "Laddu", "Payasam",
                    "Banana Chips", "Kozhukatta", "Unniyappam", "Achappam", "Mysore Pak",
                    "Bebinca", "Dodol", "Coconut Ladoo",
                ]
            )
        ),
        Cuisine(
            name: "Gujarati",
            dishes: CuisineDishes(
                breakfast: [
                    "Dhokla", "Thepla", "Fafda", "Appam", "Khakhra ghee", "Handvo",
                    "Vaghareli roti", "Locho", "Khamani sev", "Moong Dal Chilla",
                ],
                lunchDinnerVeg: [
                    "Dal Dhokli", "Undhiyu", "Kadhi", "Sev Tameta", "Vagharela Bhaat",
                    "Pulaav",
                ],
                lunchDinnerNonVeg: [],
                snacks: [
                    "Fafda", "Gathiya", "Chakri", "Mathiya", "Gujarati Samosa",
                    "Ragda Petis",
                ]
            )
        ),
        Cuisine(
            name: "Bengali",
            dishes: CuisineDishes(
                breakfast: ["Luchi", "Aloo Dum", "Puri", "Kochuri", "Poha"],
                lunchDinnerVeg: ["Dal", "Rice", "Vegetable Curry"],
                lunchDinnerNonVeg: [
                    "Fish Curry", "Chicken Curry", "Biryani", "Mutton Curry",
                ],
                snacks: [
                    "Singara", "Jhal Muri", "Tele Bhaja", "Rasgulla", "Sandesh",
                    "Mishti Doi", "Ragda Petis",
                ]
            )
        ),
        Cuisine(
            name: "Assamese",
            dishes: CuisineDishes(
                breakfast: ["Pitha", "Luchi", "Aloo Pitika", "Khar", "Til Pitha"],
                lunchDinnerVeg: ["Dal", "Rice"],
                lunchDinnerNonVeg: [
                    "Fish Curry", "Chicken Curry", "Biryani", "Masor Tenga",
                ],
                snacks: [
                    "Pitha", "Laddu", "Narikol Pitha", "Til Pitha", "Ghila Pitha",
                ]
            )
        ),
        Cuisine(
            name: "Odisha",
            dishes: CuisineDishes(
                breakfast: ["Pakhala", "Chuda", "Pitha", "Upma", "Poha"],
                lunchDinnerVeg: ["Dal", "Rice", "Vegetable Curry"],
                lunchDinnerNonVeg: ["Chicken Curry", "Fish Curry", "Biryani"],
                snacks: [
                    "Samosa", "Kachori", "Jalebi", "Gulab Jamun", "Rasgulla",
                    "Chhena Poda",
                ]
            )
        ),
    ]

    private static let universal = CuisineDishes(
        breakfast: [
            "Idli", "Dosa", "Poha", "Upma", "Bread Toast", "Cornflakes", "Sandwich",
            "Fruit Salad", "Masala Oats",
        ],
        lunchDinnerVeg: [
            "Veg Biryani", "Rajma", "Chole", "Chana Masala", "Dal Makhani",
            "Paneer Masala", "Vegetable Curry", "Mixed Vegetable", "Aloo Gobi",
            "Aloo Matar", "Palak Paneer", "Pasta", "Maggi", "Veg Fried Rice",
            "Veg Pulao", "Jeera Rice", "Dal Khichdi", "Vegetable Khichdi", "Thai Curry",
        ],
        lunchDinnerNonVeg: [
            "Chicken Curry", "Butter Chicken", "Fish Curry", "Egg Curry", "Mutton Curry",
            "Chicken Biryani", "Mutton Biryani", "Chicken Fried Rice", "Egg Fried Rice",
        ],
        snacks: [
            "Samosa", "Pakora", "Kachori", "Vada", "Bonda", "Bajji", "Jalebi",
            "Rasgulla", "Ladoo", "Besan Ladoo", "Coconut Ladoo", "Gajar Halwa",
            "Sooji Halwa", "Kheer", "Rice Kheer", "Dry Fruits", "Nuts", "Almonds",
            "Cashews", "Pistachios", "Walnuts", "Raisins", "Banana Chips",
            "Potato Chips", "Popcorn", "Biscuits", "Cookies", "Namkeen", "Mixture",
            "Dhokla", "Dahi Vada", "Dahi Puri", "Sev Puri", "Bhel Puri", "Pani Puri",
            "Chaat", "Aloo Chaat", "Fruit Chaat", "Boiled Corn", "Potato",
            "Boiled Potato", "French Fries", "Boiled Egg", "Fried Egg",
            "Scrambled Egg", "Omelette", "Egg Sandwich", "Veg Sandwich",
            "Paneer Sandwich", "Veg Burger", "Veg Pizza", "Pasta", "Spaghetti",
            "Macaroni", "Noodles",
        ]
    )

    public static var allCuisineNames: [String] { cuisines.map(\.name) }

    /// Sample dishes shown in the onboarding chip's info popover.
    public static func sampleDishes(for cuisineName: String, limit: Int = 8) -> [String] {
        guard let cuisine = cuisines.first(where: { $0.name == cuisineName }) else { return [] }
        var pool = cuisine.dishes.breakfast + cuisine.dishes.lunchDinnerVeg
        pool += cuisine.dishes.lunchDinnerNonVeg + cuisine.dishes.snacks
        var seen = Set<String>()
        return pool.filter { seen.insert($0).inserted }.prefix(limit).map { $0 }
    }

    /// Combines selected cuisine dishes with the universal pool.
    /// - Parameter vegOnly: when true, drops non-veg lunch/dinner items.
    public static func dishesFor(_ cuisineNames: [String], vegOnly: Bool = false) -> DishPool {
        let selected = cuisines.filter { cuisineNames.contains($0.name) }
        var breakfast: [String] = []
        var lunchDinner: [String] = []
        var snacks: [String] = []

        for cuisine in selected {
            breakfast += cuisine.dishes.breakfast
            lunchDinner += cuisine.dishes.lunchDinnerVeg
            if !vegOnly { lunchDinner += cuisine.dishes.lunchDinnerNonVeg }
            snacks += cuisine.dishes.snacks
        }
        breakfast += universal.breakfast
        lunchDinner += universal.lunchDinnerVeg
        if !vegOnly { lunchDinner += universal.lunchDinnerNonVeg }
        snacks += universal.snacks

        return DishPool(
            breakfast: distinct(breakfast),
            lunchDinner: distinct(lunchDinner),
            snacks: distinct(snacks)
        )
    }

    /// Order-preserving dedup, matching Kotlin's `distinct()`.
    private static func distinct(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { seen.insert($0).inserted }
    }
}
