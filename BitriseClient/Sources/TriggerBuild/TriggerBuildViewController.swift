//
//  TriggerBuildViewController.swift
//  BitriseClient
//
//  Created by Toshihiro Suzuki on 2017/12/19.
//  Copyright © 2017 toshi0383. All rights reserved.
//

import Continuum
import TKKeyboardControl
import UIKit

// TODO: Refactoring
final class TriggerBuildViewController: UIViewController, Storyboardable, UITableViewDataSource, UITableViewDelegate, UIGestureRecognizerDelegate {

    typealias Dependency = TriggerBuildLogicStore

    static func makeFromStoryboard(_ logicStore: TriggerBuildLogicStore) -> TriggerBuildViewController {
        let vc = TriggerBuildViewController.unsafeMakeFromStoryboard()
        vc.logicStore = logicStore
        return vc
    }

    @IBOutlet private weak var baseBottomConstraint: NSLayoutConstraint!

    @IBOutlet private weak var rootStackView: UIStackView!

    @IBOutlet private weak var gitObjectInputView: GitObjectInputView! {
        didSet {
            gitObjectInputView.layer.zPosition = 1.0
        }
    }

    private lazy var apiTokenTextfieldDelegate: TextFieldDelegate = {
        return TextFieldDelegate { [weak self] apiToken in
            // NOTE: retaining delegate instance by implicit strong self capture
            self?.logicStore?.apiToken = apiToken
        }
    }()

    @IBOutlet private weak var apiTokenTextfield: UITextField! {
        didSet {
            // No Continuum: `UITextField.text` keyPath didn't compile.
            apiTokenTextfield.delegate = apiTokenTextfieldDelegate
        }
    }

    @IBOutlet private weak var tableView: UITableView! {
        didSet {
            tableView.dataSource = self
            tableView.delegate = self
            tableView.allowsMultipleSelectionDuringEditing = false
        }
    }

    // MARK: Private

    private weak var lastFirstResponder: UIResponder?
    private var logicStore: TriggerBuildLogicStore!
    private let bag = ContinuumBag()

    // MARK: LifeCycle

    override func viewDidLoad() {
        super.viewDidLoad()

        // safeArea relative margin only for iPhoneX
        if !Device.isPhoneX {
            rootStackView.topAnchor.constraint(equalTo: view.topAnchor).isActive = true
        }

        // [ActionPopoverButton]
        // Tell rootStackView the hitTest target.
        rootStackView.isUserInteractionEnabled = true
        rootStackView.hth.targetChildToHitTest = gitObjectInputView

        tableView.reloadData()

        // No need to perform reactive update for apiTokenTextField.
        // Currently apiToken is not changed outside this view.
        apiTokenTextfield.text = logicStore.apiToken

        notificationCenter.continuum
            .observe(gitObjectInputView.newInput) { [weak self] value in
                if let value = value {
                    self?.logicStore.gitObject = value
                }
            }
            .disposed(by: bag)

        gitObjectInputView.updateUI(logicStore.gitObject)

        // PullToDismiss
        let gesture = UIPanGestureRecognizer(target: self, action: #selector(panGesture))
        gesture.delegate = self
        if let grs = tableView.gestureRecognizers {
            grs.forEach {
                gesture.require(toFail: $0)
            }
        }
        view.addGestureRecognizer(gesture)

        view.keyboardTriggerOffset = 44.0;    // Input view frame height

        view.addKeyboardNonpanning(frameBasedActionHandler: { [weak self] keyboardFrameInView, firstResponder, opening, closing in
            guard let me = self else { return }

            me.lastFirstResponder = firstResponder

            guard let v = firstResponder as? UIView else { return }

            if !closing {
                let keyboardY = keyboardFrameInView.minY

                // NOTE: Set no margins between the keyboard.
                //   to avoid edge case like AddNewCell at bottom on landscape with safeArea.
                //   Modal's presentingVC(BuildListVC) would be visible in background (thru the margin space),
                //   because we are moving self.view frame on keyboard appearance.
                let vMaxY = v.convert(.zero, to: me.view).y + v.frame.height // + 4

                let delta = keyboardY - vMaxY
                if delta < 0 {
                    me.view.frame.origin.y = delta
                }
            } else {
                me.view.frame.origin.y = 0
            }

            if v.isDescendant(of: me.tableView),
                let ip = me.tableView.indexPathForSelectedRow,
                opening {
                me.tableView.deselectRow(at: ip, animated: true)
            }
        })
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)

        lastFirstResponder?.resignFirstResponder()
    }

    // MARK: Handle PanGesture

    private var oldViewHeight: CGFloat = 0

    @objc func panGesture(_ gesture: UIPanGestureRecognizer) {
        switch gesture.state {
        case .ended:
            print(gesture.velocity(in: view).y)
            if gesture.translation(in: view).y > view.frame.height / 2
                || gesture.velocity(in: view).y > 250.0 {
                self.dismiss(animated: true, completion: nil)
            } else {
                view.moveTo(y: 0, animated: true)
            }
        default:
            let translationY = gesture.translation(in: view).y
            if translationY > 0.5 {
                view.moveTo(y: translationY, animated: false)
            }
        }
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {

        let location = gestureRecognizer.location(in: view)
        let viewsToIgnorePanGesture: [UIView] = [gitObjectInputView]

        for v in viewsToIgnorePanGesture {
            if v.hitTest(view.convert(location, to: v), with: nil) != nil {
                return false
            }
        }

        return true
    }

    // MARK: IBAction

    @IBAction private func triggerButton() {

        gitObjectInputView.resignFirstResponder()
        apiTokenTextfield.resignFirstResponder()

        logicStore.triggerBuild()
    }

    // MARK: UITableViewDataSource & UITableViewDelegate

    func numberOfSections(in tableView: UITableView) -> Int {
        return 4
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch section {
        case 0:
            return logicStore.workflowIDs.count
        case 1:
            return 1
        case 2:
            return logicStore.environments.count
        case 3:
            return 1
        default:
            fatalError()
        }
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        switch indexPath.section {
        case 0:
            let cell = tableView.dequeueReusableCell(withIdentifier: "Cell")!
            cell.textLabel?.text = logicStore.workflowIDs[indexPath.row]
            return cell
        case 1:
            let cell = tableView.dequeueReusableCell(withIdentifier: "AddNewCell")! as! AnyAddNewCell
            cell.configure(placeholder: "Add new workflowID") { [weak self] text in
                guard let me = self else { return }

                let ip = IndexPath(row: me.logicStore.workflowIDs.count, section: indexPath.section - 1)
                me.logicStore.appendWorkflowID(text)
                me.tableView.insertRows(at: [ip], with: UITableViewRowAnimation.automatic)
                me.tableView.scrollToRow(at: ip, at: .top, animated: true)
            }
            return cell

        case 2:
            let cell = tableView.dequeueReusableCell(withIdentifier: "EnvCell")! as! EnvCell
            let env = logicStore.environments[indexPath.row]
            cell.configure(text: env.string) { [weak self] enabled in
                guard let me = self else { return }

                me.logicStore.setEnvironmentEnabled(enabled, forKey: env.key)
            }
            return cell

        case 3:
            let cell = tableView.dequeueReusableCell(withIdentifier: "AddNewCell")! as! AnyAddNewCell
            cell.configure(placeholder: "environment e.g. PLATFORM:tvOS") { [weak self] text in
                guard let me = self else { return }

                let splitted = text.split(separator: ":").map(String.init)
                if splitted.count != 2 {
                    return
                }

                let ip = IndexPath(row: me.logicStore.environments.count, section: indexPath.section - 1)
                me.logicStore.appendEnvironment((splitted[0], splitted[1]))
                me.tableView.insertRows(at: [ip], with: UITableViewRowAnimation.automatic)
                me.tableView.scrollToRow(at: ip, at: .top, animated: true)
            }
            return cell
        default:
            fatalError()
        }
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        guard indexPath.section == 0 else { return }

        logicStore.workflowID = logicStore.workflowIDs[indexPath.row]

        lastFirstResponder?.resignFirstResponder()
    }

    func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        return indexPath.section % 2 == 0
    }

    func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCellEditingStyle, forRowAt indexPath: IndexPath) {
        if editingStyle != .delete {
            return
        }
        switch indexPath.section {
        case 0:
            logicStore.removeWorkflowID(at: indexPath.row)
            tableView.deleteRows(at: [indexPath], with: .automatic)
        case 2:
            logicStore.removeEnvironment(at: indexPath.row)
            tableView.deleteRows(at: [indexPath], with: .automatic)
        default:
            break
        }
    }
}
