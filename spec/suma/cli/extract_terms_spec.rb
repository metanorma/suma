# frozen_string_literal: true

require "suma/cli"
require "suma/utils"
require "suma/cli/extract_terms"

RSpec.describe Suma::Cli::ExtractTerms do
  subject(:test_subject) { described_class.new }

  let(:arm_exp) do
    File.expand_path(
      "../../fixtures/extract_terms/modules/activity/arm.exp", __dir__
    )
  end
  let(:mim_exp) do
    File.expand_path(
      "../../fixtures/extract_terms/modules/activity/mim.exp", __dir__
    )
  end
  let(:action_schema_exp) do
    File.expand_path(
      "../../fixtures/extract_terms/resources/action_schema/action_schema.exp",
      __dir__,
    )
  end

  context "when input is invalid" do
    it "raises ENOENT error when file not found" do
      expect do
        test_subject.extract_terms("not-found.exp")
      end.to raise_error(Errno::ENOENT)
    end

    it "raises ArgumentError error when file is not an EXPRESS file" do
      expect do
        test_subject.extract_terms(
          File.expand_path("extract_terms_spec.rb", __dir__),
        )
      end.to raise_error(ArgumentError)
    end

    it "raises ENOENT error when no files found" do
      expect do
        test_subject.extract_terms(File.expand_path(".", __dir__))
      end.to raise_error(Errno::ENOENT)
    end

    it "raises ENOTDIR error when option `output` is not a directory" do
      options = {
        output: File.expand_path("extract_terms_spec.rb", __dir__),
      }

      expect do
        test_subject.invoke(
          :extract_terms,
          [arm_exp],
          options,
        )
      end.to raise_error(Errno::ENOTDIR)
    end
  end

  context "when input is valid" do
    it "extract_terms EXPRESS files without options" do
      express_files_path = File.expand_path(
        "../../fixtures/extract_terms/modules/activity",
        __dir__,
      )

      result = test_subject.invoke(:extract_terms, [express_files_path])

      expect(result.map { |r| r["source_file"] }).to eq(
        [
          File.join(express_files_path, "arm.exp"),
          File.join(express_files_path, "mim.exp"),
        ],
      )
    end

    it "extract_terms EXPRESS files with option `recursive: true`" do # rubocop:disable RSpec/ExampleLength
      express_files_path = File.expand_path(
        "../../fixtures/extract_terms",
        __dir__,
      )

      result = test_subject.invoke(:extract_terms, [express_files_path],
                                   { recursive: true })

      expect(result.map { |r| r["source_file"] }).to eq(
        [
          File.join(express_files_path, "modules/activity/arm.exp"),
          File.join(express_files_path, "modules/activity/mim.exp"),
          File.join(express_files_path,
                    "resources/action_schema/action_schema.exp"),
        ],
      )
    end
  end

  context "when input is module exp file" do
    arm_concept_yaml = <<~CONCEPT
      ---
      id: redacted_uuid
      data:
        identifier: ISO/TC 184/SC 4/WG 12 N2941
        localized_concepts:
          eng: redacted_uuid
    CONCEPT

    mim_concept_yaml = <<~CONCEPT
      ---
      id: redacted_uuid
      data:
        identifier: ISO/TC 184/SC 4/WG 12 N1157
        localized_concepts:
          eng: redacted_uuid
    CONCEPT

    arm_localized_concept_yaml = <<~LOCALIZED_CONCEPT
      ---
      data:
        terms:
        - type: expression
          normative_status: preferred
          designation: activity
        definition:
        - content: "{{application object}} that represents the activity {{entity}}"
        notes:
        - content: An **Activity** is the identification of the occurrence of an action
            that has taken place, is taking place, or is expected to take place in the future.
            The procedure executed during that **Activity** is identified with the <<express:Activity_method_arm.Activity_method,Activity_method>>
            that is referred to by the **chosen_method** attribute.
        - content: Status information identifying the level of completion of each activity
            may be provided within an instance of <<express:Activity_arm.Activity_status,Activity_status>>.
        - content: The items that are affected by an *Activity*, for example as input or
            output, may be identified within an instance of <<express:Activity_arm.Applied_activity_assignment,Applied_activity_assignment>>.
        - content: An **Activity_relationship** is a relationship between two instances
            of <<express:Activity_arm.Activity,Activity>>.
        - content: An **Activity_status** is the assignment of a status to an <<express:Activity_arm.Activity,Activity>>
            .
        - content: An **Applied_activity_assignment** is an association of an <<express:Activity_arm.Activity,Activity>>
            with product or activity data. It characterizes the role of the concepts represented
            with these data with respect to the activity.
        - content: This entity should not be used to represent the association of an activity
            with the organizations that are responsible for its execution or its management.
            That kind of information can be represented with instances of <<express:Person_organization_assignment_arm.Organization_or_person_in_organization_assignment,Organization_or_person_in_organization_assignment>>
            .
        examples:
        - content: Change, distilling, design, a process to drill a hole, and a task such
            as training someone, are examples of activities.
        - content: The activity required to complete a work order, may be decomposed into
            a series of activities. Their corresponding instances would be related using
            instances of the *Activity_relationship* entity.
        language_code: eng
        domain: 'application module: Activity_arm'
        source:
        - type: authoritative
          origin:
            ref: ISO 10303-1047:2014 ED3
    LOCALIZED_CONCEPT

    mim_localized_concept_yaml = <<~LOCALIZED_CONCEPT
      ---
      data:
        terms:
        - type: expression
          normative_status: preferred
          designation: activity
        definition:
        - content: "{{entity data type}} that is a type of action_assignment that represents
            the activity {{entity}}"
        notes:
        - content: An **applied_action_assignment** is an <<express:action_schema.action,action>>
            related to the data that are affected by the <<express:action_schema.action,action>>.
            An **applied_action_assignment** is a type of <<express:management_resources_schema.action_assignment,action_assignment>>.
        examples: []
        language_code: eng
        domain: 'application module: Activity_mim'
        source:
        - type: authoritative
          origin:
            ref: ISO 10303-1047:2014 ED3
    LOCALIZED_CONCEPT

    it "extract_terms from `arm.exp`" do
      result = test_subject.invoke(:extract_terms, [arm_exp])

      expect(result.map { |r| r["source_file"] }).to eq([arm_exp])
      expect(strip_uuid(result.first["concept"].to_yaml))
        .to eq(arm_concept_yaml)

      expect(strip_uuid(result.first["localized_concept"].to_yaml))
        .to eq(arm_localized_concept_yaml)
    end

    it "extract_terms from `mim.exp`" do
      result = test_subject.invoke(:extract_terms, [mim_exp])

      expect(result.map { |r| r["source_file"] }).to eq([mim_exp])
      expect(strip_uuid(result.first["concept"].to_yaml))
        .to eq(mim_concept_yaml)

      expect(strip_uuid(result.first["localized_concept"].to_yaml))
        .to eq(mim_localized_concept_yaml)
    end
  end

  context "when input is resource exp file" do
    concept_yaml = <<~CONCEPT
      ---
      id: redacted_uuid
      data:
        identifier: ISO/TC 184/SC 4/WG 12 N10693
        localized_concepts:
          eng: redacted_uuid
    CONCEPT

    localized_concept_yaml = <<~LOCALIZED_CONCEPT
      ---
      data:
        terms:
        - type: expression
          normative_status: preferred
          designation: fundamentals_of_product_description_and_support
        definition:
        - content: "{{entity data type}} that represents the fundamentals_of_product_description_and_support
            {{entity}}"
        notes:
        - content: |-
            An **action** is the identification of the occurrence of an activity and a description of its result.

            An **action** identifies an activity that has taken place, is taking place, or is expected to take place in the future.

            An action has a definition that is specified by an <<express:action_schema.action_method,action_method>>.
        - content: In particular application domains, terms such as task, process, activity,
            operation, and event may be synonyms for *action*.
        - content: An **action_directive** is an authoritative instrument that provides
            directions to achieve the specified results.
        - content: An **action_method** is the definition of an activity. This definition
            includes the activity's objectives and effects.
        - content: This definition may be the basis for actions or the solution for action
            requests.
        - content: An **action_method_relationship** is a relationship between two instances
            of the entity data type <<express:action_schema.action_method,action_method>>
            and provides an identification and description of this relationship.
        - content: The role of *action_method_relationship* can be defined in the annotated
            EXPRESS schemas that use or specialize this entity, or by default, in an agreement
            of common understanding between the partners sharing this information.
        - content: This entity, together with the <<express:action_schema.action_method,action_method>>
            entity, is based on the relationship template that is described in annex E.3.
        - content: This entity may be used to define a procedural relationship among constituent
            activities.
        - content: An **action_relationship** is a relationship between two instances of
            the entity data type <<express:action_schema.action,action>> and provides an
            identification and description of this relationship.
        - content: The role of *action_relationship* can be defined in the annotated EXPRESS
            schemas that use or specialize this entity, or by default, in an agreement of
            common understanding between the partners sharing this information.
        - content: An **action_request_solution** is an association between a <<express:action_schema.versioned_action_request,versioned_action_request>>
            and an <<express:action_schema.action_method,action_method>> that is a potential
            solution for the request.
        - content: An **action_request_status** is the association of a status with a <<express:action_schema.versioned_action_request,versioned_action_request>>.
        - content: An **action_resource** is a thing that is identified as being needed
            to carry out an action.
        - content: An **action_resource_relationship** is a relationship between two instances
            of the entity data type <<express:action_schema.action_resource,action_resource>>
            and provides an identification and description of this relationship.
        - content: The role of *action_resource_relationship* can be defined in the annotated
            EXPRESS schemas that use or specialize this entity, or by default, in an agreement
            of common understanding between the partners sharing this information.
        - content: This entity, together with the <<express:action_schema.action_resource,action_resource>>
            entity, is based on the relationship template that is described in annex E.3.
        - content: An **action_resource_type** is the identification of the kind of <<express:action_schema.action_resource,action_resource>>
            needed to carry out an action.
        - content: An **action_status** is the association of a status with an <<express:action_schema.executed_action,executed_action>>.
        - content: Information about the date and time may be associated with the *action_status*
            through the use of <<express:management_resources_schema.date_assignment,date_assignment>>,
            <<express:management_resources_schema.date_and_time_assignment,date_and_time_assignment>>,
            or <<express:management_resources_schema.time_assignment,time_assignment>>.
        - content: A **directed_action** is a type of <<express:action_schema.executed_action,executed_action>>
            that is governed by an <<express:action_schema.action_directive,action_directive>>.
        - content: A **directed_action_assignment** is an association of a <<express:action_schema.directed_action,directed_action>>
            with product data.
        - content: An **executed_action** is a type of <<express:action_schema.action,action>>
            that is completed, partially completed, or just identified. It may but need
            not have status information associated with it.
        - content: The role of *executed_action* can be defined in the annotated EXPRESS
            schemas that use or specialize this entity, or by default, in an agreement of
            common understanding between the partners sharing this information.
        - content: Status information is associated to *executed_action* through <<express:action_schema.action_status,action_status>>.
        - content: A **versioned_action_request** is a specification of a desired result.
        - content: The desired result being identified and described may be obtained through
            one of more <<express:action_schema.action_method,action_method>>s.
        - content: A **versioned_action_request_relationship** is a relationship between
            two <<express:action_schema.versioned_action_request,versioned_action_request>>
            objects.
        - content: An **action_directive_relationship** is a relationship between two <<express:action_schema.action_directive,action_directive>>
            objects.
        examples:
        - content: Change, distilling, design, a process to drill a hole, and a task such
            as training someone are examples of actions.
        - content: ISO Directives Part 3 provides guidance for the development of standards
            documents within ISO.
        - content: For the <<express:action_schema.action,action>> whose name attribute
            is 'serve dinner', the name attribute of related instance of *action_method*
            could be 'cook by recipe' or 'purchase takeout food'.
        - content: This entity may be used to specify the kind of tool needed to perform
            a process operation.
        - content: A *directed_action* could be the inspection of a building as directed
            by city officials according to the city building codes for earthquake safety.
            The action is the inspection of the building. The directive is issued by city
            officials guided by the city building codes. In an application protocol, the
            building authority may be associated with an <<express:management_resources_schema.organization_assignment,organization_assignment>>.
            The building codes may be associated with a <<express:management_resources_schema.document_reference,document_reference>>.
        - content: An *executed_action* could be to 'paint the office' with a status of
            'scheduled'. The action is 'paint the office'. The status further qualifies
            the action as 'planned', 'scheduled', or 'completed'.
        - content: Two <<express:action_schema.versioned_action_request,versioned_action_request>>
            objects may be related if they address similar problems.
        - content: A <<express:action_schema.versioned_action_request,versioned_action_request>>
            may be a version of a work request. It might be related to a different version
            of the work request using a *versioned_action_request_relationship*.
        language_code: eng
        domain: 'resource: action_schema'
        source:
        - type: authoritative
          origin:
            ref: ISO 10303-41:2025 ED8
    LOCALIZED_CONCEPT

    it "extract_terms from `action_schema.exp`" do
      result = test_subject.invoke(:extract_terms, [action_schema_exp])

      expect(result.map { |r| r["source_file"] }).to eq([action_schema_exp])
      expect(strip_uuid(result.first["concept"].to_yaml))
        .to eq(concept_yaml)

      expect(strip_uuid(result.first["localized_concept"].to_yaml))
        .to eq(localized_concept_yaml)
    end
  end
end
