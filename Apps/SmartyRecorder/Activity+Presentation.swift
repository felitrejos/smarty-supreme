import SmartyCore

extension Activity {
    var title: String {
        switch self {
        case .swings(let stroke, let strength): "\(stroke.rawValue.capitalized) · \(strength.rawValue.capitalized)"
        case .nonSwing(let activity): activity.title
        case .still: "Holding still"
        }
    }

    var instructions: String {
        switch self {
        case .swings(let stroke, let strength):
            "Hold your thumb anywhere on the screen during each \(strength.rawValue) \(stroke.rawValue) swing, then lift it. Aim for 17 swings."
        case .nonSwing(let activity):
            activity.instructions + " Aim for 3 minutes."
        case .still:
            "Hold the phone upright, pointing at where the Mac would be, and keep still. Aim for 3 minutes."
        }
    }
}

extension NonSwingActivity {
    var title: String {
        switch self {
        case .walking: "Walking"
        case .pickUpPutDown: "Picking up and putting down"
        case .typing: "Typing"
        case .handOver: "Handing it to someone"
        case .wavingWhileTalking: "Waving while talking"
        }
    }

    var instructions: String {
        switch self {
        case .walking: "Walk around normally with the phone in your hand."
        case .pickUpPutDown: "Put the phone on a table and pick it up again, over and over."
        case .typing: "Type on the phone as you normally would."
        case .handOver: "Hand the phone to someone and take it back, over and over."
        case .wavingWhileTalking: "Talk and gesture with the phone in your hand."
        }
    }
}
