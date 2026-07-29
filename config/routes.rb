Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check

  root "interventions#pending"

  resources :interventions, only: [:index, :new, :create, :show] do
    member do
      post :cancel
      post :resolve # PM marks action_required / call_failed / no_show as handled
    end
    collection do
      get :pending
      get :in_progress
      get :tracking
      get :export, defaults: { format: "csv" }
    end
    resources :calls, only: [], controller: "calls" do
      member do
        get :transcript
      end
    end
  end

  resources :technicians, only: [:index, :new, :create]
  resource :pm_profile, only: [:new, :create, :edit, :update], controller: "pm_profile"

  get "dashboard", to: "dashboard#show"
  get "audit_logs", to: "audit_logs#index"

  # Public, tokenized, no-login report editing page for technicians
  get   "reports/:token/edit", to: "reports#edit",   as: :edit_report
  patch "reports/:token",      to: "reports#update", as: :report

  namespace :webhooks do
    post "call_e", to: "call_e#create"
    post "sms_technician", to: "sms_technician#create"
  end

  # Technician-facing account area — separate auth from the PM interface
  # (which has none, per our single-PM MVP assumption). See SPEC.md 3bis.
  # Uses `scope` rather than `namespace` so the URL/route-helper prefix stays
  # "technician" while the Ruby module is "technician_portal" — avoids a
  # naming collision with the top-level Technician model.
  scope module: "technician_portal", path: "technician", as: "technician" do
    get  "login",  to: "sessions#new"
    post "login",  to: "sessions#create"
    delete "logout", to: "sessions#destroy"

    post "login_code", to: "login_codes#create"

    get  "activate/:token", to: "activations#new",    as: :activation
    post "activate/:token", to: "activations#create"

    get  "confirm", to: "confirmations#new"
    post "confirm", to: "confirmations#create"

    root to: "interventions#index"
    resources :interventions, only: [:index, :show] do
      member do
        post :accept
        post :start_intervention
      end
    end
  end
end
