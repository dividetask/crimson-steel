# Reusable confirm-and-post stub. Renders a short message
# above a single button that POSTs to `action`. Used by the
# Turn Action stub's Move and End Turn panels — anywhere that
# wants "are you sure?" with one click.

helpers do
  def confirm_action_stub(message:, action:, label: 'Confirm')
    erb :"stubs/_confirm_action_stub", layout: false, locals: {
      message: message, action: action, label: label
    }
  end
end
