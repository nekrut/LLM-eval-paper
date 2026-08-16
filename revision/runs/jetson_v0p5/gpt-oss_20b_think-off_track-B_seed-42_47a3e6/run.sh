#!/usr/bin/env bash
set -euo pipefail

samples=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")
results_dir="results"
ref="data/ref/chrM.fa"

mkdir -p "$results_dir"

# Index reference for BWA if needed
if ! [[ -f "${ref}.amb" && -f "${ref}.ann" && -f "${ref}.bwt" && -f "${ref}.pac" && -f "${ref}.sa" ]]; then
    bwa index "$ref"
fi

# Index reference fasta for samtools if needed
if ! [[ -f "${ref}.fai" ]]; then
    samtools faidx "$ref"
fi

processed=false

for sample in "${samples[@]}"; do
    bam="${results_dir}/${sample}.bam"
    bai="${results_dir}/${sample}.bai"
    vcf_gz="${results_dir}/${sample}.vcf.gz"
    tbi="${results_dir}/${sample}.vcf.gz.tbi"

    if [[ -f "$bam" && -f "$bai" && -f "$vcf_gz" && -f "$tbi" ]]; then
        continue
    fi

    fq1="data/raw/${sample}_1.fq.gz"
    fq2="data/raw/${sample}_2.fq.gz"

    bwa mem -t 4 "$ref" "$fq1" "$fq2" | samtools view -Sb - | samtools sort -@ 4 -o "$bam"
    samtools index "$bam"

    lofreq call -f "$ref" -b "$bam" | bcftools view -O z -o "$vcf_gz" -
    tabix -p vcf "$vcf_gz"

    processed=true
done

collapsed="${results_dir}/collapsed.tsv"
if [[ "$processed" == true || ! -f "$collapsed" ]]; then
    printf "sample\tchrom\tpos\tref\talt\taf\n" > "${collapsed}.tmp"
    for sample in "${samples[@]}"; do
        vcf_gz="${results_dir}/${sample}.vcf.gz"
        awk -v samp="$sample" '
            BEGIN{FS="\t"}
            /^#/ {next}
            {
                chrom=$1; pos=$2; ref=$4; alt=$5;
                info=$7;
                match(info, /AF=([^;]+)/, arr);
                af = (arr[1] != "") ? arr[1] : ".";
                print samp"\t"chrom"\t"pos"\t"ref"\t"alt"\t"af
            }
        ' "$vcf_gz" >> "${collapsed}.tmp"
    done
    mv "${collapsed}.tmp" "$collapsed"
fi

exit 0