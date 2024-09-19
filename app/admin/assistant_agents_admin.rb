# frozen_string_literal: true

Trestle.resource(:assistant_agents) do
  menu do
    item :assistant_agents, icon: 'fa fa-star'
  end

  form do |_aa|
    row do
      col(sm: 4) do
        text_field :name
      end
      col(sm: 4) do
        text_field :name_en
      end
    end

    text_field :category

    text_field :version
    text_area :system_message
    text_area :prompt_header
    text_area :helper_agent_system_message
    text_area :conclude_conversation_message
    text_field :description

    json_editor :llm_config
    json_editor :meta

    collection_select :agent_tool_ids, AgentTool.all, :id, :name, { label: '可使用工具(s)' }, { multiple: true }
  end

  # Customize the table columns shown on the index view.
  #
  table do
    column :name
    column :description
    column :version
    column :category
    # column :created_at, align: :center
    column :duplicate, header: '複製', align: :center do |obj|
      button_to '複製', duplicate_assistant_agents_admin_path(obj), class: 'btn btn-primary btn-block'
    end
    actions
  end

  controller do
    def duplicate
      aa = AssistantAgent.find(params[:id])
      dup_aa = aa.dup
      dup_aa['name'] = "#{dup_aa['name']}#{複製}"
      dup_aa.version = DateTime.current.to_date
      dup_aa.save
      redirect_back(fallback_location: assistant_agents_admin_path)
    end
  end

  routes do
    post :duplicate, on: :member
  end
end
