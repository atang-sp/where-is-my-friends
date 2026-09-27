import Component from "@glimmer/component";
import LoginLocaleSwitcher from "../../components/login-locale-switcher";

export default class LoginBeforeModalBodySwitcher extends Component {
  static shouldRender(_args, { currentUser, siteSettings }) {
    return !currentUser && siteSettings?.where_is_my_friends_enabled !== false;
  }

  <template><LoginLocaleSwitcher /></template>
}
