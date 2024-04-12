module Contabilidad
  # Clase en la cual se define que informacion guardar en cada
  # atributo de la linea contable
  class BaseService

    def initialize(empresa, variable, liquidacions)
      # Los elementos se añaden en el método 'add_line'
      @obj_contabilidad = nil
      @liquidacions = liquidacions
      @empresa = empresa
      @variable = variable
    end

    def obj_contabilidad interfaz: nil, empresa: nil, on_progress: nil  # rubocop:todo Buk/MemoizeWithParameters
      @obj_contabilidad ||=       
          @liquidacions.each_with_index do |liq, index|
            liq.linea_liquidacions.each(&:add_line)
          end
        end
    end

    def generate
      Exportador::Contabilidad::Personalizadas.new().generate_doc(@empresa, @variable, @obj_contabilidad)
    end

    protected

      def add_line(cuenta_contable, deber, haber, glosa, mostrar_icr: true, prefix: nil, forzar_centro_costo: nil, payment_receiver: nil, tratos: nil, line_code: nil, description: nil, item_code: nil, pension_saving: nil, negativo: false,
                   receptor: nil)
        return unless any_nonzero?(deber, haber)

        linea = LineaContable.new(
          rut: @employee.rut,
          person_id: @employee.person_id,
          employee_id: @employee.id,
          employee_code: @employee.code,
          employee: @employee,
          last_name: @employee.last_name,
          first_name: @employee.first_name,
          second_last_name: @employee.segundo_apellido,
          area_full_name: @job.cached_area&.full_name,
          division_id: @job.cached_area&.department&.cached_division&.id,
          division_name: @job.cached_area&.department&.cached_division&.name,
          department_name: @job.cached_area&.department&.name,
          role_name: @job.role&.name,
          role_code: @job.role&.code,
          employee_custom_attrs: @employee.custom_attrs.as_hash,
          job_custom_attrs: @job.custom_attrs&.as_hash,
          role_custom_attrs: @job.role&.custom_attrs&.as_hash,
          area_custom_attrs: @job.cached_area&.custom_attrs&.as_hash,
          cuenta_custom_attrs: cuenta_contable&.custom_attrs&.as_hash,
          division_custom_attrs: @job.cached_area&.department&.cached_division&.custom_attrs,
          cuenta_contable: cuenta,
          deber: deber,
          haber: haber,
          glosa: glosa,
          deber_o_haber: debit_or_credit,
          monto: monto,
          mostrar_icr: mostrar_icr,
          nombre_cuenta: cuenta_contable&.nombre,
          tipo_cuenta: cuenta_contable&.tipo,
          tipo_doc: cuenta_contable&.tipo_doc,
          formato: cuenta_contable&.formato || "detalle",
          origin: @origin,
          area_name: @job.cached_area&.name,
          afp: @plan.try(:fondo_cotizacion_print),
          apvc: @plan.try(:apvc),
          isapre: @plan.try(:health_company_print),
          afp_recaudadora: @plan.try(:afp_recaudadora),
          rut_afp: @plan.try(:rut_fondo_cotizacion_print),
          rut_isapre: @plan.try(:rut_health_company_print),
          rol_privado: @employee.rol_privado,
          dias_trabajados: dias_trabajados,
          costo_empresa: costo_empresa,
          rut_recipient: payment_receiver&.rut,
          first_name_recipient: payment_receiver&.first_name,
          last_name_recipient: payment_receiver&.last_name,
          email_recipient: payment_receiver&.email,
          payment_method_recipient: payment_receiver&.payment_detail&.payment_method,
          bank_recipient: payment_receiver&.payment_detail&.bank,
          account_type_recipient: payment_receiver&.payment_detail&.account_type,
          account_number_recipient: payment_receiver&.payment_detail&.account_number,
          estado: @employee.estado,
          rut_apv: search_rut_apv(cuenta_contable, item_code, pension_saving),
          regimen_apv: search_regimen_apv(cuenta_contable, item_code, pension_saving),
          institucion_apv: search_institucion_apv(cuenta_contable, item_code, pension_saving),
          description: description,
          item_code: item_code,
          tipo_contrato: @job.tipo_contrato,
          job: @job,
          tratos: tratos,
          is_cuenta2: is_cuenta2,
          compania_cuenta2: compania_cuenta2,
          rut_cuenta2: rut_cuenta2,
          rut_afp_recaudadora: rut_afp_recaudadora_cesantia[@plan&.afp_recaudadora&.to_sym].presence,
          receptor: receptor,
          negativo: negativo,
          line_code: line_code,
          union_rut: @job.cached_union&.rut,
          area_centro_costo: @job.area&.centro_costo_definition&.code,
        )
        @obj_contabilidad.concat(linea)
      end
end
