Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check

  root "interventions#pending"

  resources :interventions, only: [:index, :new, :create, :show] do
    member do
      post :start
      post :resolve # PM marks action_required / call_failed / no_show as handled
    end
    collection do
      get :pending
      get :in_progress
      get :tracking
      get :export, defaults: { format: "csv" }
    end
  end

  resources :technicians, only: [:index, :new, :create] do
    member do
      post :consent
    end
  end

  get "dashboard", to: "dashboard#show"
  get "audit_logs", to: "audit_logs#index"

  # Public, tokenized, no-login report editing page for technicians
  get   "reports/:token/edit", to: "reports#edit",   as: :edit_report
  patch "reports/:token",      to: "reports#update", as: :report

  namespace :webhooks do
    post "call_e", to: "call_e#create"
    post "sms_technician", to: "sms_technician#create"
  end
end
