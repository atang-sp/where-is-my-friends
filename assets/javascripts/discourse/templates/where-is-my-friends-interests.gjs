import InterestOnboardingPage from "../components/interest-onboarding-page";

export default <template>
  <InterestOnboardingPage
    @inviteTo={{@controller.invite_to}}
    @model={{@model}}
  />
</template>
