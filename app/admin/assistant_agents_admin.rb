Trestle.resource(:assistant_agents) do
  menu do
    item :assistant_agents, icon: "fa fa-star"
  end

  form do |aa|
    row do
      col(sm: 4) {
        text_field :name
      }
      col(sm: 4) {
        text_field :name_en
      }
    end
    
    text_field :version
    text_field :system_message
    text_field :description

    json_editor :llm_config
    json_editor :meta
  end

  # Customize the table columns shown on the index view.
  #
  # table do
  #   column :name
  #   column :created_at, align: :center
  #   actions
  # end

  # Customize the form fields shown on the new/edit views.
  #
  # form do |assistant_agent|
  #   text_field :name
  #
  #   row do
  #     col { datetime_field :updated_at }
  #     col { datetime_field :created_at }
  #   end
  # end

  # By default, all parameters passed to the update and create actions will be
  # permitted. If you do not have full trust in your users, you should explicitly
  # define the list of permitted parameters.
  #
  # For further information, see the Rails documentation on Strong Parameters:
  #   http://guides.rubyonrails.org/action_controller_overview.html#strong-parameters
  #
  # params do |params|
  #   params.require(:assistant_agent).permit(:name, ...)
  # end
end
