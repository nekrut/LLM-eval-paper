#!/usr/bin/env bash
set -euo pipefail
THREADS=4
mkdir -p results
samples=(M117-bl M117-ch M117C1-bl M117C1-ch)
ref=data/ref/chrM.fa
index_prefix=${ref}.fai
if [[ ! -e ${index_prefix} ]]; then
    samtools faidx ${ref}
fi
bwa_index_ref=$(ls data/ref/*.amb 2>/dev/null || true)
if [[ -z "${bwa_index_ref}" ]]; then
    bwa index ${ref}
fi
for sample in "${samples[@]}"; do
    fastq1=data/raw/${sample}_1.fq.gz
    fastq2=data/raw/${sample}_2.fq.gz
    rg="@RG\\tID:${sample}\\tSM:${sample}\\tLB:${sample}\\tPL:ILLUMINA"
    bwa_output=results/${sample}.bam
    if [[ -e ${bwa_output} && -e ${bwa_output}.bai && newer ${fastq1} ${fastq2} ${bwa_output} ]]; then
        :
    else
        bwa mem -t ${THREADS} -R "${rg}" ${ref} ${fastq1} ${fastq2} |
            samtools sort -@ ${THREADS} -o ${bwa_output}
    fi
    if [[ -e results/${sample}.bam.bai && newer ${bwa_output} results/${sample}.bam.bai ]]; then
        :
    else
        samtools index -@ ${THREADS} results/${sample}.bam
    fi
    vcf=results/${sample}.vcf
    if [[ -e ${vcf}.gz.tbi && newer ${bwa_output} ${vcf}.gz.tbi ]]; then
        :
    else
        lofreq call-parallel --pp-threads ${THREADS} --ref ${ref} --out ${vcf} results/${sample}.bam
        bgzip -c ${vcf} > ${vcf}.gz
        rm -f ${vcf}
        tabix -p vcf ${vcf}.gz
    fi
done
collapsed=results/collapsed.tsv
if [[ ! -e ${collapsed} || ${collapsed} -ot *.vcf.gz ]]; then
    {
        echo -e "sample\tchrom\tpos\tref\talt\taf"
        for sample in "${samples[@]}"; do
            bcftools query -f '{{sample}}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n' results/${sample}.vcf.gz
        done
    } | bgzip > ${collapsed}.gz
    tabix -p vcf ${collapsed}.gz
fi