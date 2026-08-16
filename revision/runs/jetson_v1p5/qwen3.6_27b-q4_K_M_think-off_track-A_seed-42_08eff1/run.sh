#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLES=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")
mkdir -p results

# 1. Reference indexing — BWA (idempotent: bwa index skips if .bwt exists)
if [[ ! -f data/ref/chrM.fa.bwt ]]; then
    bwa index data/ref/chrM.fa
fi

# 2. Reference indexing — samtools faidx (idempotent: samtools faidx skips if .fai exists)
if [[ ! -f data/ref/chrM.fa.fai ]]; then
    samtools faidx data/ref/chrM.fa
fi

# Per-sample processing
for sample in "${SAMPLES[@]}"; do
    bam_file="results/${sample}.bam"
    bai_file="results/${sample}.bam.bai"
    vcf_file="results/${sample}.vcf.gz"
    tbi_file="results/${sample}.vcf.gz.tbi"

    # 3. Per-sample alignment + sort (idempotent: skip if BAM exists)
    if [[ ! -f "${bam_file}" ]]; then
        bwa mem -t ${THREADS} \
            -R "@RG\tID:${sample}\tSM:${sample}\tLB:${sample}\tPL:ILLUMINA" \
            data/ref/chrM.fa \
            "data/raw/${sample}_1.fq.gz" \
            "data/raw/${sample}_2.fq.gz" | \
        samtools sort -@ ${THREADS} -o "${bam_file}" -
    fi

    # 4. BAM index (idempotent: skip if BAI exists)
    if [[ ! -f "${bai_file}" ]]; then
        samtools index -@ ${THREADS} "${bam_file}"
    fi

    # 5. Variant calling — LoFreq (idempotent: skip if VCF.gz exists)
    # Note: lofreq call-parallel outputs to stdout or file. We use -o for file output.
    # We check for the final compressed VCF to determine if work is done.
    if [[ ! -f "${vcf_file}" ]]; then
        # LoFreq outputs uncompressed VCF by default when using -o, unless specified otherwise.
        # The plan says: lofreq call-parallel ... -o results/{sample}.vcf
        # Then step 6 compresses it.
        # So we need to check if the intermediate .vcf exists or just run if final .vcf.gz is missing.
        # To be safe and idempotent, we can check if the final product exists.
        
        # Run lofreq into a temporary uncompressed file or directly? 
        # The plan implies: lofreq -> results/{sample}.vcf (uncompressed)
        # Then bgzip -> results/{sample}.vcf.gz
        
        # Let's create the uncompressed VCF if missing
        vcf_uncompressed="results/${sample}.vcf"
        if [[ ! -f "${vcf_uncompressed}" ]]; then
            lofreq call-parallel --pp-threads ${THREADS} \
                -f data/ref/chrM.fa \
                -o "${vcf_uncompressed}" \
                "${bam_file}"
        fi

        # 6. VCF compression + tabix index (idempotent: skip if .gz and .tbi exist)
        if [[ ! -f "${vcf_file}" ]]; then
            bgzip -f "${vcf_uncompressed}"
        fi
        
        if [[ ! -f "${tbi_file}" ]]; then
            tabix -p vcf "${vcf_file}"
        fi
    fi
done

# 7. Collapsed TSV (idempotent: overwrite or append? Plan says printf > then >>)
# To be idempotent and correct, we regenerate the header and append all samples.
# If results/collapsed.tsv exists, we can just recreate it. It's fast.
printf 'sample\tchrom\tpos\tref\talt\taf\n' > results/collapsed.tsv

for sample in "${SAMPLES[@]}"; do
    vcf_file="results/${sample}.vcf.gz"
    # bcftools query to extract fields, then awk to prepend sample name
    bcftools query -f '%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n' "${vcf_file}" | \
        awk -v s="${sample}" 'BEGIN{OFS="\t"}{print s,$0}' >> results/collapsed.tsv
done