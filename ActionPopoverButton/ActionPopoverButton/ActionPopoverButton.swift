import UIKit

private final class _HorizontalStackView: UIStackView {

    override init(frame: CGRect) { super.init(frame: frame); configure(); }
    required init(coder: NSCoder) { super.init(coder: coder); configure(); }

    private func configure() {
        distribution = .equalSpacing
        alignment = .center
        axis = .horizontal
        spacing = 10
    }

}

private final class _ActionView: UIView {

    let alphaView: UIView = .init()

    var arrangedSubviews: [UIView] {
        return actions.map { $0.view }
    }

    let actions: [Action]

    required init?(coder aDecoder: NSCoder) { fatalError() }

    init(actions: [Action]) {

        self.actions = actions

        super.init(frame: .zero)

        translatesAutoresizingMaskIntoConstraints = false

        do {
            alphaView.layer.cornerRadius = 2
            addSubview(alphaView)
            alphaView.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                alphaView.topAnchor.constraint(equalTo: topAnchor),
                alphaView.bottomAnchor.constraint(equalTo: bottomAnchor),
                alphaView.leadingAnchor.constraint(equalTo: leadingAnchor),
                alphaView.trailingAnchor.constraint(equalTo: trailingAnchor),
            ])
        }

        do {
            let stackView = _HorizontalStackView(arrangedSubviews: arrangedSubviews)
            addSubview(stackView)
            stackView.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                topAnchor.constraint(equalTo: stackView.topAnchor, constant: -4),
                bottomAnchor.constraint(equalTo: stackView.bottomAnchor, constant: 4),
                leadingAnchor.constraint(equalTo: stackView.leadingAnchor, constant: -8),
                trailingAnchor.constraint(equalTo: stackView.trailingAnchor, constant: 8),
            ])
        }

        unhighlight()
    }

    override func updateConstraints() {
        super.updateConstraints()
        NSLayoutConstraint.activate([
            topAnchor.constraint(equalTo: superview!.bottomAnchor, constant: 8),
            leadingAnchor.constraint(equalTo: superview!.leadingAnchor, constant: 4),
        ])
    }

    func highlight() {
        alphaView.backgroundColor = UIColor(hex: 0xDDDDDD)
    }

    func unhighlight() {
        alphaView.backgroundColor = UIColor(hex: 0x999999)
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesMoved(touches, with: event)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesEnded(touches, with: event)
        if let point = touches.first?.location(in: self), let hit = hitTest(point, with: event) {
            if let action = actions.first(where: { $0.view == hit }) {
                action.onTapBlock()
            }
        }
    }
}

private final class Action {

    let view: UIView
    let onTapBlock: (() -> ())

    init(view: UIView, onTapBlock: @escaping () -> ()) {
        self.view = view
        self.onTapBlock = onTapBlock
    }
}

/// Interactive popover view without UIPopoverController.
///
/// Add ActionPopoverButton as subview.
/// Popover stackview will show-up on either on tap or on dragging.
/// Currently it shows up under the bottom of it's parent.
///
/// [FEATURES]
/// - Custom views for each button
/// - User tap is handled by UIGestureRecognizer registered internally.
/// - Buttons are highlighted on tap by modifying alpha to 0.5
///
/// [Handling Touches Correctly]
/// In most cases, popped stackview won't receive any touch.
/// This is because the stackview is rendered outside of it's parent's bounds.
/// Make sure you don't cut the hitTest chain by either:
///
/// - subclassing and implementing override hitTest for each parents of the ActionPopoverButton
///
/// or
///
/// - using `UIView.hth.targetChildToHitTest` to archive that behavior without subclassing.
///   Call `UIView.hth.exchangeMethods()` in your AppDelegate on launch to make automatic hitTest delegation work.
///
/// [TODO]
/// - Customizable spacing
/// - Customizable style (circle)
/// - Automatically decide popping position
open class ActionPopoverButton: UIView {

    public var touchedAlpha: CGFloat = 0.5

    private var actions: [Action] = []
    private var _onFocusActionChanged: (() -> ())?

    public func addActionButton(_ view: UIView, onTapBlock: @escaping () -> ()) {
        let action = Action(view: view, onTapBlock: onTapBlock)
        actions.append(action)
    }

    /// Called each time the focused view is changed by dragging (touchesMoved).
    /// Not called on tap or touchesEnded.
    public func onFocusActionChanged(_ block: @escaping () -> ()) {
        _onFocusActionChanged = block
    }

    open override func didMoveToSuperview() {
        super.didMoveToSuperview()

        // IMPORTANT to draw stackview outside the bounds.
        clipsToBounds = false
    }

    private var show: Bool = false

    private func updateUI(show: Bool? = nil) {
        let show = show ?? !self.show
        guard show != self.show else { return }
        self.show = show
        if show {
            showActionView(animated: true)
        } else {
            hideActionView(animated: true)
        }
    }

    private var actionView: _ActionView?

    private func _perform(animated: Bool, _ animations: @escaping () -> ()) {
        if !animated {
            animations()
        } else {
            UIView.animate(withDuration: 0.1, animations: animations)
        }
    }

    private func hideActionView(animated: Bool) {
        _perform(animated: animated) {
            self.actionView?.alpha = 0.0
        }
    }

    private func showActionView(animated: Bool) {
        if actionView == nil {
            actionView = _ActionView(actions: actions)
            actionView!.alpha = 0.0
            addSubview(actionView!)
            for action in actions {
                let actionGesture = UITapGestureRecognizer(target: self, action: #selector(actionTap))
                action.view.addGestureRecognizer(actionGesture)
            }
        }
        _perform(animated: animated) {
            self.actionView?.alpha = 1.0
        }
    }

    @objc private func actionTap(_ sender: UIView) {
        actions.first(where: { $0.view == sender })?.onTapBlock()
        actionView?.alpha = 0.0
    }

    private var workItem: DispatchWorkItem?

    private var touchesBeganTime: TimeInterval? {
        didSet {
            if touchesBeganTime != nil {
                workItem?.cancel()
                workItem = DispatchWorkItem {
                    self.updateUI(show: true)
                }
                DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + 0.3, execute: workItem!)
            } else {
                workItem?.cancel()
                workItem = nil
            }
        }
    }
    open override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)

        touchesBeganTime = Date().timeIntervalSince1970
    }

    open override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesMoved(touches, with: event)

        if let touch = touches.first {
            if let actionView = actionView, let hit = actionView.hitTest(touch.location(in: actionView), with: event) {
                var unhighlightTargets = actionView.arrangedSubviews
                if actionView.arrangedSubviews.contains(hit) {
                    if let idx = unhighlightTargets.index(of: hit) {
                        unhighlightTargets.remove(at: idx)
                    }
                    if hit.alpha != 0.5 {
                        hit.alpha = 0.5

                        if let time = touchesBeganTime,
                            Date().timeIntervalSince1970 - time > 0.1 {
                            _onFocusActionChanged?()
                        }
                    }
                }
                unhighlightTargets.forEach { $0.alpha = 1.0 }
            } else {
                actionView?.arrangedSubviews.forEach { $0.alpha = 1.0 }
            }
        }
    }

    open override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesEnded(touches, with: event)

        guard let touch = touches.first else { return }

        if let time = touchesBeganTime {
            let interval = Date().timeIntervalSince1970 - time
            if interval < 1 {
                if hitTest(touch.location(in: self), with: event) != nil {
                    if let action = actions.first(where: { $0.view.hitTest(touch.location(in: $0.view), with: event) == $0.view }) {
                        // touchUp actionView's button
                        action.onTapBlock()
                        updateUI(show: false)
                    } else {
                        // touchUp self
                        updateUI()
                    }
                }
            } else if 1 < interval {
                // after longPress
                if let action = actions.first(where: { $0.view.hitTest(touch.location(in: $0.view), with: event) != nil }) {
                    action.onTapBlock()
                }
                updateUI(show: false)
            }
        }
        touchesBeganTime = nil
    }

    open override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        if let hit = super.hitTest(point, with: event) {
            // It's me, then. That was easy.
            return hit
        }

        if let actionView = actionView {

            // Is it inside the actionView, which is outside of my bounds?
            if actionView.hitTest(convert(point, to: actionView), with: event) != nil {
                return self
            }
        }
        return nil
    }
}

